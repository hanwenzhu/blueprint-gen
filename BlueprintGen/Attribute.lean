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
  uses : Option (Array Name) := none
  /-- The set of nodes that the proof of this node depends on. Infers from the constant's value if not present. -/
  proofUses : Option (Array Name) := none
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
syntax blueprintOptions := (str)? (ppSpace blueprintOption)*

/-- The `blueprint` attribute tags a constant to add to the blueprint. -/
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
        let uses ← ids.mapM realizeGlobalConstNoOverloadWithInfo
        config := { config with uses }
      | `(blueprintOption| (proofUses := [$[$ids],*])) =>
        let proofUses ← ids.mapM realizeGlobalConstNoOverloadWithInfo
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

def hasProof (name : Name) (cfg : Config) : CoreM Bool := do
  return cfg.hasProof.getD (wasOriginallyTheorem (← getEnv) name)

/-- Returns a pair of sets (constants used by statement, constants used by proof).
They are disjoint except that possibly both contain `sorryAx`. -/
def usedConstants (name : Name) : CoreM (NameSet × NameSet) := do
  let env ← getEnv
  let info ← getConstInfo name
  -- TODO: constructors in case of structure/inductive
  let typeUsed := info.type.getUsedConstantsAsSet
  let valueUsed := match info.value? with
    | some value => value.getUsedConstantsAsSet
    | none => ∅
  -- User-declared constants with the `using` tactic
  let proofUsing := NameSet.ofArray (getProofUsing env name)

  let statementUsed := typeUsed
  let proofUsed := valueUsed ∪ proofUsing

  return (statementUsed, proofUsed \ statementUsed.erase ``sorryAx)

def mkStatementPart (name : Name) (cfg : Config) (hasProof : Bool) (used : NameSet) :
    CoreM NodePart := do
  let env ← getEnv
  let uses := cfg.uses.getD (used.filter fun c => (blueprintExt.find? env c).isSome).toArray
  return {
    leanOk := !used.contains ``sorryAx
    text := ((← findSimpleDocString? env name).getD "").trim
    uses
    latexEnv := cfg.latexEnv.getD (if hasProof then "theorem" else "definition")
  }

def mkProofPart (name : Name) (cfg : Config) (used : NameSet) : CoreM NodePart := do
  let env ← getEnv
  let uses := cfg.proofUses.getD (used.filter fun c => (blueprintExt.find? env c).isSome).toArray
  -- Use proof docstring for proof text
  let proof := cfg.proof.getD ("\n\n".intercalate (getProofDocString env name).toList)
  return {
    leanOk := !used.contains ``sorryAx
    text := proof
    uses
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
    add := fun name stx kind => do
      unless kind == AttributeKind.global do throwError "invalid attribute 'blueprint', must be global"
      let cfg ← elabBlueprintConfig stx
      withOptions (·.updateBool `trace.blueprint (cfg.trace || ·)) do

      let node ← mkNode name cfg
      blueprintExt.add name node
      trace[blueprint] "Blueprint node added:\n{repr node}"

      let range := match ← getDeclarationRange? stx with
        | some range => range
        | none =>
          -- for synthetic `[blueprint]`, put at end of file
          { pos := ⟨1000000000, 0⟩, charUtf16 := 0, endPos := ⟨1000000000, 0⟩, endCharUtf16 := 0 }
      modifyEnv fun env => addMainModuleBlueprintInput env {
        data := .node node
        declarationRange := range
      }
      -- pushInfoLeaf <| .ofTermInfo {
      --   elaborator := .anonymous, lctx := {}, expectedType? := none,
      --   stx, expr := mkStrLit (repr node).pretty }
  }

end BlueprintGen
