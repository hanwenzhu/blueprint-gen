import Lean
import Batteries.Lean.NameMapAttribute


open Lean Elab

namespace BlueprintGen

/-- The statement or proof of a node. -/
structure NodePart where
  /-- Whether the part is formalized without `sorry` in Lean. -/
  leanOk : Bool
  /-- The natural language description of this part. -/
  text : String
  /-- The names of nodes that this node depends on. -/
  uses : Array Name
  /-- The LaTeX environment to use for this part. -/
  latexEnv : String
deriving Inhabited, Repr, ToJson, ToExpr

/-- A theorem or definition in the blueprint graph. -/
structure Node where
  /-- The Lean name of the tagged constant. -/
  name : Name
  /-- The statement of this node. -/
  statement : NodePart
  /-- The proof of this node. -/
  proof : Option NodePart
  /-- The surrounding environment is not ready to be formalized, typically because it requires more blueprint work. -/
  notReady : Bool
  /-- A GitHub issue number where the surrounding definition or statement is discussed. -/
  discussion : Option Nat
  /-- The short title of the node in LaTeX. -/
  title : Option String
deriving Inhabited, Repr, ToExpr

initialize registerTraceClass `blueprint

/-- Environment extension that stores the nodes of the blueprint. -/
initialize blueprintExt : NameMapExtension Node ← registerNameMapExtension _

end BlueprintGen
