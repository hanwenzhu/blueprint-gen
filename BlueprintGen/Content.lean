import BlueprintGen.Basic


open Lean Elab

namespace BlueprintGen

/-! The blueprint content in a module (see `BlueprintContent`) consists of:

- All module docs
- Input content from other librarys or modules (similar to LaTeX `\input`)
- Blueprint nodes, either manually input or generated from a `@[blueprint]` annotation

These contents are sorted by declaration range (similar to the sort in doc-gen4).
-/

/-- An input to the blueprint without the declaration range -/
inductive BlueprintInputData where
  | inputLibrary : Name → BlueprintInputData
  | inputModule : Name → BlueprintInputData
  | node : Node → BlueprintInputData
deriving Inhabited, Repr

/-- An input to the blueprint.
Together with `ModuleDoc`s, these determine the blueprint content of a module (see `BlueprintContent`). -/
structure BlueprintInput where
  data : BlueprintInputData
  declarationRange : DeclarationRange
deriving Inhabited, Repr

/-- An environment extension storing `BlueprintInput`s (similar to the module doc extension). -/
initialize blueprintInputExt : SimplePersistentEnvExtension BlueprintInput (PersistentArray BlueprintInput) ←
  registerSimplePersistentEnvExtension {
    addImportedFn := fun _ => {}
    addEntryFn := fun s e => s.push e
  }

def addMainModuleBlueprintInput (env : Environment) (input : BlueprintInput) : Environment :=
  blueprintInputExt.addEntry env input

def getMainModuleBlueprintInput (env : Environment) : PersistentArray BlueprintInput :=
  blueprintInputExt.getState env

def getBlueprintInput? (env : Environment) (moduleName : Name) : Option (Array BlueprintInput) :=
  env.getModuleIdx? moduleName |>.map fun modIdx =>
    blueprintInputExt.getModuleEntries env modIdx

elab "blueprint_input_module" mod:ident : command => do
  let range := (← getDeclarationRange? (← getRef)).get!
  modifyEnv fun env => addMainModuleBlueprintInput env {
    data := .inputModule mod.getId
    declarationRange := range
  }

elab "blueprint_input_library" lib:ident : command => do
  let range := (← getDeclarationRange? (← getRef)).get!
  modifyEnv fun env => addMainModuleBlueprintInput env {
    data := .inputLibrary lib.getId
    declarationRange := range
  }

elab "blueprint_input_node" decl:ident : command => do
  let env ← getEnv
  let name ← Command.liftCoreM <| realizeGlobalConstNoOverloadWithInfo decl
  match blueprintExt.find? env name with
  | none => throwError "{name} does not have attribute `[blueprint]`"
  | some node =>
    let range := (← getDeclarationRange? (← getRef)).get!
    modifyEnv fun env => addMainModuleBlueprintInput env {
      data := .node node
      declarationRange := range
    }

deriving instance Repr for ModuleDoc in
/-- The export blueprint LaTeX from a module is determined by the list of `BlueprintContent`
in the module. This is analogous to doc-gen4's `ModuleMember`. -/
inductive BlueprintContent where
  | input : BlueprintInput → BlueprintContent
  | modDoc : ModuleDoc → BlueprintContent
deriving Inhabited, Repr

def BlueprintContent.declarationRange : BlueprintContent → DeclarationRange
  | input i => i.declarationRange
  | modDoc doc => doc.declarationRange

/--
An order for blueprint contents, based on their declaration range.
-/
def BlueprintContent.order (l r : BlueprintContent) : Bool :=
  Position.lt l.declarationRange.pos r.declarationRange.pos

/-- Get blueprint contents of the current module (this is for debugging). -/
def getMainModuleBlueprintContents (env : Environment) : Array BlueprintContent :=
  let inputs := getMainModuleBlueprintInput env |>.map BlueprintContent.input
  let modDocs := getMainModuleDoc env |>.map BlueprintContent.modDoc
  (inputs ++ modDocs).toArray.qsort BlueprintContent.order

/-- Get blueprint contents of an imported module (this is for debugging). -/
def getBlueprintContents (env : Environment) (module : Name) : Array BlueprintContent :=
  let inputs := getBlueprintInput? env module |>.getD #[] |>.map BlueprintContent.input
  let modDocs := getModuleDoc? env module |>.getD #[] |>.map BlueprintContent.modDoc
  (inputs ++ modDocs).qsort BlueprintContent.order

end BlueprintGen
