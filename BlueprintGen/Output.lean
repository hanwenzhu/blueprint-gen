import BlueprintGen.Content


open Lean

namespace BlueprintGen

section ToLatex

inductive LatexPart where
  | input : System.FilePath → LatexPart
  | content : String → LatexPart

abbrev Latex := Array LatexPart

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

def Node.toLatex (node : Node) : CoreM Latex := do
  trace[blueprint] "Converting {repr node} to LaTeX"

  -- position string as annotation
  let env ← getEnv
  let module := match env.getModuleIdxFor? node.name with
    | some modIdx => env.allImportedModuleNames[modIdx]!
    | none => env.header.mainModule
  let fileName := modToFilePath "." module "lean"
  let declarationRange := (← findDeclarationRanges? node.name).map (·.range)
  let rangeStr := match declarationRange with
    | none => ""
    | some range => s!":{range.pos.line}.{range.pos.column}-{range.endPos.line}.{range.endPos.column}"
  let posStr := s!"{fileName}{rangeStr}"

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

def BlueprintInputData.toLatex : BlueprintInputData → CoreM Latex
  | .inputLibrary lib => do
    return #[.input (libraryToRelPath lib "tex")]
  | .inputModule mod => do
    return #[.input (moduleToRelPath mod "tex")]
  | .node n => n.toLatex

def BlueprintInput.toLatex (i : BlueprintInput) : CoreM Latex :=
  i.data.toLatex

def BlueprintContent.toLatex : BlueprintContent → CoreM Latex
  | .input i => i.toLatex
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

def Node.toJson (node : Node) : CoreM Json := do
  trace[blueprint] "Converting {repr node} to JSON"

  let env ← getEnv
  let module := match env.getModuleIdxFor? node.name with
    | some modIdx => env.allImportedModuleNames[modIdx]!
    | none => env.header.mainModule
  let fileName := modToFilePath "." module "lean"
  let declarationRange := (← findDeclarationRanges? node.name).map (·.range)

  return json% {
    "name": $(node.name),
    "statement": $(node.statement),
    "proof": $(node.proof),
    "notReady": $(node.notReady),
    "discussion": $(node.discussion),
    "title": $(node.title),
    "declarationRange": $(declarationRange.map rangeToJson),
    "module": $(module),
    "file": $(fileName)
  }

def BlueprintContent.toJson : BlueprintContent → CoreM Json
  | .input { data := .inputLibrary lib, .. } => return json% {"type": "inputLibrary", "data": $(lib)}
  | .input { data := .inputModule mod, .. } => return json% {"type": "inputModule", "data": $(mod)}
  | .input { data := .node node, .. } => return json% {"type": "node", "data": $(← node.toJson)}
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
