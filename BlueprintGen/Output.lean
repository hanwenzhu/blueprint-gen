import BlueprintGen.Content
import MD4Lean


open Lean

namespace BlueprintGen

section ToLatex

inductive LatexPart where
  /-- \input{file} in LaTeX. -/
  | input : System.FilePath → LatexPart
  /-- Raw LaTeX content. -/
  | content : String → LatexPart
deriving Repr

abbrev Latex := Array LatexPart

/-!
We convert docstrings of declarations and modules to LaTeX,
by the following steps:

1. If possible, we convert citations (e.g. `[taylorwiles]`) to \cite{taylorwiles} commands.
2. Using MD4Lean, we parse the markdown.
3. If possible, we convert inline code with a constant (e.g. `abc`) to \ref{abc} commands.
4. We convert the markdown to LaTeX.

The long-term goal for blueprint-gen is to migrate to Verso.
Here, this would mean using docstring parsing from Verso instead
(which similarly uses MD4Lean to parse the docstrings),
but has support for trying to elaborate code blocks.
However, it currently does not support citations in docstrings.
-/

/- Largely copied from `findAllReferences` in doc-gen4. -/
/-- Find all references in a markdown text. -/
partial def findAllReferences (refsMap : Std.HashMap String BibItem) (s : String) (i : String.Pos := 0)
    (ret : Std.HashSet String := ∅) : Std.HashSet String :=
  let lps := s.posOfAux '[' s.endPos i
  if lps < s.endPos then
    let lpe := s.posOfAux ']' s.endPos lps
    if lpe < s.endPos then
      let citekey := Substring.toString ⟨s, ⟨lps.1 + 1⟩, lpe⟩
      match refsMap[citekey]? with
      | .some _ => findAllReferences refsMap s lpe (ret.insert citekey)
      | .none => findAllReferences refsMap s lpe ret
    else
      ret
  else
    ret

def markdownToLatex (markdown : String) : CoreM Latex := do
  match MD4Lean.parse markdown with
  | none => return #[.content markdown]
  | some doc => documentToLatex doc
where
  documentToLatex (doc : MD4Lean.Document) : CoreM Latex := do
    return (← doc.blocks.mapM blockToLatex).map .content
  blockToLatex (block : MD4Lean.Block) : CoreM String := do
    match block with
    | .p texts =>
      return String.join (← texts.mapM textToLatex).toList
    | .ul _tight _mark items =>
      return "\\begin{itemize}" ++ "\n\n".intercalate (← items.mapM itemToLatex).toList ++ "\\end{itemize}"
    | .ol _tight _start _mark items =>
      return "\\begin{enumerate}" ++ "\n\n".intercalate (← items.mapM itemToLatex).toList ++ "\\end{enumerate}"
    | .hr => return "\\midrule"
    | .header level texts =>
      let headerCommand := match level with | 1 => "section" | 2 => "subsection" | 3 => "subsubsection" | 4 => "paragraph" | _ => "subparagraph"
      return "\\" ++ headerCommand ++ "{" ++ String.join (← texts.mapM textToLatex).toList ++ "}"
    | .code _info _lang _fenceChar content => return "\\begin{verbatim}" ++ "\n\n".intercalate content.toList ++ "\\end{verbatim}"
    | .html content => return String.join content.toList
    | .blockquote content => return "\\begin{quote}" ++ "\n\n".intercalate (← content.mapM blockToLatex).toList ++ "\\end{quote}"
    | .table _head _body => throwError "Table not supported"
  textToLatex (text : MD4Lean.Text) : CoreM String := do
    match text with
    | .normal content => return content
    | .nullchar => return ""
    | .br content => return content
    | .softbr content => return content
    | .entity content => return content
    | .em texts => return "\\emph{" ++ String.join (← texts.mapM textToLatex).toList ++ "}"
    | .strong texts => return "\\textbf{" ++ String.join (← texts.mapM textToLatex).toList ++ "}"
    | .u texts => return "\\ul{" ++ String.join (← texts.mapM textToLatex).toList ++ "}"
    | .a href _title _isAuto texts => return "\\href{" ++ String.join (← href.mapM attrTextToLatex).toList ++ "}{" ++ String.join (← texts.mapM textToLatex).toList ++ "}"
    | .img src _title _alt => return "\\includegraphics{" ++ String.join (← src.mapM attrTextToLatex).toList ++ "}"
    | .code content => return "\\texttt{" ++ String.join content.toList ++ "}"
    | .del texts => return "\\st{" ++ String.join (← texts.mapM textToLatex).toList ++ "}"
    | .latexMath content => return "$" ++ String.join content.toList ++ "$"
    | .latexMathDisplay content => return "$$" ++ String.join content.toList ++ "$$"
    | .wikiLink target texts => return "\\href{" ++ String.join (← target.mapM attrTextToLatex).toList ++ "}{" ++ String.join (← texts.mapM textToLatex).toList ++ "}"
  attrTextToLatex (attrText : MD4Lean.AttrText) : CoreM String := do
    match attrText with
    | .normal content => return content
    | .entity content => return content
    | .nullchar => return ""
  itemToLatex (item : MD4Lean.Li MD4Lean.Block) : CoreM String := do
    match item with
    | .li _isTask _taskChar _taskMarkOffset blocks =>
      return "\\item " ++ "\n\n".intercalate (← blocks.mapM blockToLatex).toList

#eval markdownToLatex "Hello, [and]"  -- copy doc-gen / verso flags!


def libraryToRelPath (library : Name) (ext : String) : System.FilePath :=
  System.mkFilePath ["library", library.toString (escape := false)] |>.addExtension ext

def moduleToRelPath (module : Name) (ext : String) : System.FilePath :=
  modToFilePath "module" module ext

def Latex.toString (latex : Latex) (basePath : System.FilePath := ".") : String :=
  let parts := latex.map fun
    | .input file => "\\input{" ++ (basePath / file).toString ++ "}"
    | .content str => str
  "\n\n".intercalate parts.toList ++ "\n"

def NodePart.toLatex (part : NodePart) (title : Option String) (additionalContent : String) : CoreM Latex := do
  let env ← getEnv
  let mut out := ""
  out := out ++ "\\begin{" ++ part.latexEnv ++ "}"
  if let some title := title then
    out := out ++ s!"[{title}]"
  if part.leanOk then
    out := out ++ "\\leanok{}"
  if !part.uses.isEmpty then
    -- Filter to used constants that are tagged with `[blueprint]`
    let uses := part.uses.filter fun c => (blueprintExt.find? env c).isSome
    out := out ++ "\\uses{" ++ ",".intercalate (uses.toList.map (·.toString)) ++ "}"
  out := out ++ part.text
  out := out ++ additionalContent
  out := out ++ "\\end{" ++ part.latexEnv ++ "}"
  return #[.content out]

def NodeWithPos.toLatex (node : NodeWithPos) : CoreM Latex := do
  -- position string as annotation
  let rangeStr := match node.location with
    | none => ""
    | some location => s!":{location.range.pos.line}.{location.range.pos.column}-{location.range.endPos.line}.{location.range.endPos.column}"
  let posStr := s!"{node.file}{rangeStr}"

  let mut addLatex := ""
  addLatex := addLatex ++ "\\lean{" ++ node.name.toString ++ "}"
  addLatex := addLatex ++ "\\label{" ++ node.name.toString ++ "}"
  if node.notReady then
    addLatex := addLatex ++ "\\notready"
  if let some d := node.discussion then
    addLatex := addLatex ++ "\\discussion{" ++ toString d ++ "}"
  addLatex := addLatex ++ s!"\n% at {posStr}\n"

  let statementLatex ← node.statement.toLatex node.title addLatex
  match node.proof with
  | none => return statementLatex
  | some proof =>
    let proofLatex ← proof.toLatex none ""
    return statementLatex ++ proofLatex

def Node.toLatex (node : Node) : CoreM Latex := do
  trace[blueprint] "Converting {repr node} to LaTeX"
  let nodeWithPos ← node.toNodeWithPos
  nodeWithPos.toLatex

def BlueprintEntryData.toLatex : BlueprintEntryData → CoreM Latex
  | .includeLibrary lib => do
    return #[.input (libraryToRelPath lib "tex")]
  | .includeModule mod => do
    return #[.input (moduleToRelPath mod "tex")]
  | .node n => n.toLatex

def BlueprintEntry.toLatex (i : BlueprintEntry) : CoreM Latex :=
  i.data.toLatex

def BlueprintContent.toLatex : BlueprintContent → CoreM Latex
  | .entry i => i.toLatex
  | .modDoc d => pure #[.content d.doc]

def moduleToLatex (module : Name) : CoreM Latex := do
  let latexes ← (getBlueprintContents (← getEnv) module).mapM BlueprintContent.toLatex
  return latexes.flatten

def mainModuleToLatex : CoreM Latex := do
  let latexes ← (getMainModuleBlueprintContents (← getEnv)).mapM BlueprintContent.toLatex
  return latexes.flatten

/-- Shows the blueprint LaTeX of the current module for debugging. -/
syntax (name := show_blueprint) "#show_blueprint" (ppSpace ident)? : command

open Elab Command in
@[command_elab show_blueprint] def elabShowBlueprint : CommandElab
  | `(command| #show_blueprint) => do
    let latex ← liftCoreM mainModuleToLatex
    logInfo m!"Exported blueprint LaTeX of current module:\n\n{latex.toString}"
  | `(command| #show_blueprint $mod:ident) => do
    let mod := mod.getId
    if (← getEnv).getModuleIdx? mod |>.isNone then
      throwError "Unknown module {mod}"
    let latex ← liftCoreM <| moduleToLatex mod
    logInfo m!"Exported blueprint LaTeX of module {mod}:\n\n{latex.toString}"
  | _ => throwUnsupportedSyntax

end ToLatex

section ToJson

private def rangeToJson (range : DeclarationRange) : Json :=
  json% {
    "pos": $(range.pos),
    "endPos": $(range.endPos)
  }

private def locationToJson (location : DeclarationLocation) : Json :=
  json% {
    "module": $(location.module),
    "range": $(rangeToJson location.range)
  }

def NodeWithPos.toJson (node : NodeWithPos) : Json :=
  json% {
    "name": $(node.name),
    "statement": $(node.statement),
    "proof": $(node.proof),
    "notReady": $(node.notReady),
    "discussion": $(node.discussion),
    "title": $(node.title),
    "hasLean": $(node.hasLean),
    "file": $(node.file),
    "location": $(node.location.map locationToJson)
  }

def Node.toJson (node : Node) : CoreM Json := do
  trace[blueprint] "Converting {repr node} to JSON"
  let nodeWithPos ← node.toNodeWithPos
  return nodeWithPos.toJson

def BlueprintContent.toJson : BlueprintContent → CoreM Json
  | .entry { data := .includeLibrary lib, .. } => return json% {"type": "includeLibrary", "data": $(lib)}
  | .entry { data := .includeModule mod, .. } => return json% {"type": "includeModule", "data": $(mod)}
  | .entry { data := .node node, .. } => return json% {"type": "node", "data": $(← node.toJson)}
  | .modDoc d => return json% {"type": "moduleDoc", "data": $(d.doc)}

def moduleToJson (module : Name) : CoreM Json := do
  return Json.arr <|
    ← (getBlueprintContents (← getEnv) module).mapM BlueprintContent.toJson

def mainModuleToJson : CoreM Json := do
  return Json.arr <|
    ← (getMainModuleBlueprintContents (← getEnv)).mapM BlueprintContent.toJson

/-- Shows the blueprint JSON of the current module for debugging. -/
syntax (name := show_blueprint_json) "#show_blueprint_json" (ppSpace ident)? : command

open Elab Command in
@[command_elab show_blueprint_json] def elabShowBlueprintJson : CommandElab
  | `(command| #show_blueprint_json) => do
    let json ← liftCoreM mainModuleToJson
    logInfo m!"Exported blueprint JSON of current module:\n\n{json}"
  | `(command| #show_blueprint_json $mod:ident) => do
    let mod := mod.getId
    if (← getEnv).getModuleIdx? mod |>.isNone then
      throwError "Unknown module {mod}"
    let json ← liftCoreM <| moduleToJson mod
    logInfo m!"Exported blueprint JSON of module {mod}:\n\n{json}"
  | _ => throwUnsupportedSyntax

end ToJson

open IO

/-- Write the result `content` to the appropriate blueprint file with extension `ext` ("tex" or "json"). -/
def outputResultsWithExt (basePath : System.FilePath) (module : Name) (content : String) (ext : String) : IO Unit := do
  FS.createDirAll basePath
  let filePath := basePath / moduleToRelPath module ext
  if let some d := filePath.parent then
    FS.createDirAll d
  FS.writeFile filePath content

/-- Write `latex` to the appropriate blueprint tex file. -/
def outputLatexResults (basePath : System.FilePath) (module : Name) (latex : Latex) : IO Unit := do
  let content := latex.toString basePath
  outputResultsWithExt basePath module content "tex"

/-- Write `json` to the appropriate blueprint json file. -/
def outputJsonResults (basePath : System.FilePath) (module : Name) (json : Json) : IO Unit := do
  let content := json.pretty
  outputResultsWithExt basePath module content "json"

/-- Write to an appropriate index tex file that \inputs all modules in a library. -/
def outputLibraryLatex (basePath : System.FilePath) (library : Name) (modules : Array Name) : IO Unit := do
  FS.createDirAll basePath
  let latex : Latex := modules.map fun mod => .input (moduleToRelPath mod "tex")
  let content := latex.toString basePath
  let filePath := basePath / libraryToRelPath library "tex"
  if let some d := filePath.parent then
    FS.createDirAll d
  FS.writeFile filePath content

/-- Write to an appropriate index json file containing paths to json files of all modules in a library. -/
def outputLibraryJson (basePath : System.FilePath) (library : Name) (modules : Array Name) : IO Unit := do
  FS.createDirAll basePath
  let json : Json := Json.mkObj [("modules", toJson (modules.map fun mod => moduleToRelPath mod "json"))]
  let content := json.pretty
  let filePath := basePath / libraryToRelPath library "json"
  if let some d := filePath.parent then
    FS.createDirAll d
  FS.writeFile filePath content

end BlueprintGen
