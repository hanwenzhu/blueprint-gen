import Lean
import Batteries.Lean.NameMapAttribute


open Lean Elab Tactic

namespace BlueprintGen

namespace ProofDocString

/-! Here we implement docstrings but for proofs. -/

-- NB: I copied some logic from `aliasExtension`

abbrev State := SMap Name (Array String)
abbrev Entry := Name × String

private def addEntryFn (s : State) (e : Entry) : State :=
  match s.find? e.1 with
  | none => s.insert e.1 #[e.2]
  | some es => s.insert e.1 (es.push e.2)

initialize proofDocStringExt : SimplePersistentEnvExtension Entry State ←
  registerSimplePersistentEnvExtension {
    addEntryFn := addEntryFn
    addImportedFn := fun es => mkStateFromImportedEntries addEntryFn {} es |>.switch
    asyncMode := .async .asyncEnv
  }

end ProofDocString

open ProofDocString

def addProofDocString (env : Environment) (name : Name) (doc : String) : Environment :=
  proofDocStringExt.addEntry (asyncDecl := name) env (name, doc)

def getProofDocString (env : Environment) (name : Name) : Array String :=
  proofDocStringExt.getState (asyncDecl := name) env |>.findD name #[]

elab docComment:docComment : tactic => do
  let some name ← Term.getDeclName? | throwError "could not get declaration name"
  validateDocComment docComment
  let doc := (← getDocStringText docComment).trim
  modifyEnv fun env => addProofDocString env name doc

/-! We implement the `using` tactic that declares used constants. -/

namespace ProofUsing

abbrev State := SMap Name (Array Name)
abbrev Entry := Name × Name

private def addEntryFn (s : State) (e : Entry) : State :=
  match s.find? e.1 with
  | none => s.insert e.1 #[e.2]
  | some es => s.insert e.1 (es.push e.2)

initialize proofUsingExt : SimplePersistentEnvExtension Entry State ←
  registerSimplePersistentEnvExtension {
    addEntryFn := addEntryFn
    addImportedFn := fun es => mkStateFromImportedEntries addEntryFn {} es |>.switch
    asyncMode := .async .asyncEnv
  }

end ProofUsing

open ProofUsing

def addProofUsing (env : Environment) (name : Name) (used : Name) : Environment :=
  proofUsingExt.addEntry (asyncDecl := name) env (name, used)

def getProofUsing (env : Environment) (name : Name) : Array Name :=
  proofUsingExt.getState (asyncDecl := name) env |>.findD name #[]

elab "using" ids:(ppSpace colGt ident)+ : tactic => do
  let some name ← Term.getDeclName? | throwError "could not get declaration name"
  for id in ids do
    let used ← realizeGlobalConstNoOverloadWithInfo id
    modifyEnv fun env => addProofUsing env name used

end BlueprintGen
