import Lean
import Batteries.Data.NameSet
import BlueprintGen.Content
import BlueprintGen.Tactic


open Lean Meta Elab

namespace BlueprintGen

/-- `Config` is the type of arguments that can be provided to `blueprint`. -/
structure Config where
  /-- By default, only theorems have separate proof parts. This option overrides this behavior. -/
  hasProof : Option Bool := none
  /-- The proof of the node in text. Uses proof docstrings if not present. -/
  proof : Option String := none
  /-- The set of nodes that this node depends on. Infers from the constant if not present. -/
  uses : Array Name := #[]
  /-- The set of nodes that the proof of this node depends on. Infers from the constant's value if not present. -/
  proofUses : Array Name := #[]
  /-- The surrounding environment is not ready to be formalized, typically because it requires more blueprint work. -/
  notReady : Bool := false
  /-- A GitHub issue number where the surrounding definition or statement is discussed. -/
  discussion : Option Nat := none
  /-- The short title of the node in LaTeX. -/
  title : Option String := none
  /-- The LaTeX environment to use for the node. -/
  latexEnv : Option String := none
  /-- Enable debugging. -/
  trace : Bool := false
deriving Repr

syntax blueprintHasProofOption := &"hasProof" " := " ("true" <|> "false")
syntax blueprintProofOption := &"proof" " := " docComment
syntax blueprintUsesOption := &"uses" " := " "[" ident,* "]"
syntax blueprintProofUsesOption := &"proofUses" " := " "[" ident,* "]"
syntax blueprintNotReadyOption := &"notReady" " := " ("true" <|> "false")
syntax blueprintDiscussionOption := &"discussion" " := " num
syntax blueprintLatexEnvOption := &"latexEnv" " := " str

syntax blueprintOption := "("
  blueprintHasProofOption <|> blueprintProofOption <|>
  blueprintUsesOption <|> blueprintProofUsesOption <|>
  blueprintNotReadyOption <|> blueprintDiscussionOption <|>
  blueprintLatexEnvOption ")"
syntax blueprintOptions := (ppSpace str)? (ppSpace blueprintOption)*

/--
The `blueprint` attribute tags a constant to add to the blueprint.

You may optionally add:
- `"Title"`: The title of the node in LaTeX.
- `hasProof := true`: If the node has a proof (default: true if the node is a theorem).
- `proof := /-- ... -/`: The proof of the node in text.
- `uses := [a, b]`: The dependencies of the node (default: inferred from the used constants).
- `proofUses := [a, b]`: The dependencies of the proof of the node (default: inferred from the used constants).
- `notReady := true`: Whether the node is not ready.
- `discussion := 123`: The discussion issue number of the node.
- `latexEnv := "lemma"`: The LaTeX environment to use for the node (default: "theorem" or "definition").

For more information, see [blueprint-gen](https://github.com/hanwenzhu/blueprint-gen).

Use `blueprint?` to show the raw data of the added node.
-/
syntax (name := blueprint) "blueprint" "?"? blueprintOptions : attr

@[inherit_doc blueprint]
macro "blueprint?" opts:blueprintOptions : attr => `(attr| blueprint ? $opts)

/-- Elaborates the configuration options for `blueprint`. -/
def elabBlueprintConfig : Syntax → CoreM Config
  | `(attr| blueprint%$_tk $[?%$trace?]? $[$title?:str]? $[$opts:blueprintOption]*) => do
    let mut config : Config := { trace := trace?.isSome }
    if let some title := title? then config := { config with title := title.getString }
    for stx in opts do
      match stx with
      | `(blueprintOption| (hasProof := true)) =>
        config := { config with hasProof := some .true }
      | `(blueprintOption| (hasProof := false)) =>
        config := { config with hasProof := some .false }
      | `(blueprintOption| (proof := $doc)) =>
        validateDocComment doc
        let proof := (← getDocStringText doc).trim
        config := { config with proof }
      | `(blueprintOption| (uses := [$[$ids],*])) =>
        let uses ← ids.mapM tryResolveConst
        config := { config with uses }
      | `(blueprintOption| (proofUses := [$[$ids],*])) =>
        let proofUses ← ids.mapM tryResolveConst
        config := { config with proofUses }
      | `(blueprintOption| (notReady := true)) =>
        config := { config with notReady := .true }
      | `(blueprintOption| (notReady := false)) =>
        config := { config with notReady := .false }
      | `(blueprintOption| (discussion := $n)) =>
        config := { config with discussion := n.getNat }
      | `(blueprintOption| (latexEnv := $str)) =>
        config := { config with latexEnv := str.getString }
      | _ => throwUnsupportedSyntax
    return config
  | _ => throwUnsupportedSyntax

/-- Whether a node has a proof part. -/
def hasProof (name : Name) (cfg : Config) : CoreM Bool := do
  return cfg.hasProof.getD (cfg.proof.isSome || wasOriginallyTheorem (← getEnv) name)

/-- Returns a pair of sets (constants used by statement, constants used by proof).
They are disjoint except that possibly both contain `sorryAx`. -/
def usedConstants (name : Name) : CoreM (NameSet × NameSet) := do
  let info ← getConstInfo name
  -- TODO: constructors in case of structure/inductive
  let typeUsed := info.type.getUsedConstantsAsSet
  let valueUsed := match info.value? with
    | some value => value.getUsedConstantsAsSet
    | none => ∅

  return (typeUsed, valueUsed \ typeUsed.erase ``sorryAx)

def mkStatementPart (name : Name) (cfg : Config) (hasProof : Bool) (used : NameSet) :
    CoreM NodePart := do
  let env ← getEnv
  -- Used constants = constants specified by `uses :=` + blueprint constants used in the statement
  let uses := used.filter fun c => (blueprintExt.find? env c).isSome
  let uses := cfg.uses.foldl (·.insert ·) uses
  -- Use docstring for statement text
  let statement := ((← findSimpleDocString? env name).getD "").trim
  return {
    leanOk := !used.contains ``sorryAx
    text := statement
    uses := uses.toArray
    latexEnv := cfg.latexEnv.getD (if hasProof then "theorem" else "definition")
  }

def mkProofPart (name : Name) (cfg : Config) (used : NameSet) : CoreM NodePart := do
  let env ← getEnv
  -- Used constants = constants specified by `proofUses :=` + blueprint constants used in the proof
  let uses := used.filter fun c => (blueprintExt.find? env c).isSome
  let uses := cfg.proofUses.foldl (·.insert ·) uses
  -- Use proof docstring for proof text
  let proof := cfg.proof.getD ("\n\n".intercalate (getProofDocString env name).toList)
  return {
    leanOk := !used.contains ``sorryAx
    text := proof
    uses := uses.toArray
    latexEnv := "proof"
  }

def mkNode (name : Name) (cfg : Config) : CoreM Node := do
  let (statementUsed, proofUsed) ← usedConstants name
  if ← hasProof name cfg then
    let statement ← mkStatementPart name cfg .true statementUsed
    let proof ← mkProofPart name cfg proofUsed
    return { cfg with name, statement, proof }
  else
    let used := statementUsed ∪ proofUsed
    let statement ← mkStatementPart name cfg .false used
    return { cfg with name, statement, proof := none }

initialize registerBuiltinAttribute {
    name := `blueprint
    descr := "Adds a node to the blueprint"
    applicationTime := .afterCompilation
    add := fun name stx kind => do
      unless kind == AttributeKind.global do throwError "invalid attribute 'blueprint', must be global"
      let cfg ← elabBlueprintConfig stx
      withOptions (·.updateBool `trace.blueprint (cfg.trace || ·)) do

      let node ← mkNode name cfg
      blueprintExt.add name node
      trace[blueprint] "Blueprint node added:\n{repr node}"

      -- pushInfoLeaf <| .ofTermInfo {
      --   elaborator := .anonymous, lctx := {}, expectedType? := none,
      --   stx, expr := mkStrLit (repr node).pretty }
  }

end BlueprintGen
