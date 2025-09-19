import BlueprintGen.Basic


open Lean Elab

namespace BlueprintGen

/-! The blueprint content in a module (see `BlueprintContent`) consists of:

- Included content from other librarys or modules (similar to LaTeX `\input`)
- Blueprint nodes, either manually included or generated from a `@[blueprint]` annotation
- All module docstrings defined in `/-! ... -/`

These contents are sorted by declaration range (similar to the sort in doc-gen4).
-/

/-- An entry to the blueprint. -/
inductive BlueprintEntryData where
  | includeLibrary : Name → BlueprintEntryData
  | includeModule : Name → BlueprintEntryData
  | node : Node → BlueprintEntryData
deriving Inhabited, Repr

/-- An entry to the blueprint.
Together with `ModuleDoc`s, these determine the blueprint content of a module (see `BlueprintContent`). -/
structure BlueprintEntry where
  data : BlueprintEntryData
  declarationRange : DeclarationRange
deriving Inhabited, Repr

/-- An environment extension storing `BlueprintEntry`s (similar to the module doc extension). -/
initialize blueprintEntryExt : SimplePersistentEnvExtension BlueprintEntry (PersistentArray BlueprintEntry) ←
  registerSimplePersistentEnvExtension {
    addImportedFn := fun _ => {}
    addEntryFn := fun s e => s.push e
  }

def addMainModuleBlueprintEntry (env : Environment) (entry : BlueprintEntry) : Environment :=
  blueprintEntryExt.addEntry env entry

def getMainModuleBlueprintEntry (env : Environment) : PersistentArray BlueprintEntry :=
  blueprintEntryExt.getState env

def getBlueprintEntry? (env : Environment) (moduleName : Name) : Option (Array BlueprintEntry) :=
  env.getModuleIdx? moduleName |>.map fun modIdx =>
    blueprintEntryExt.getModuleEntries env modIdx

elab "blueprint_include_module" mod:ident : command => do
  let range := (← getDeclarationRange? (← getRef)).get!
  modifyEnv fun env => addMainModuleBlueprintEntry env {
    data := .includeModule mod.getId
    declarationRange := range
  }

elab "blueprint_include_library" lib:ident : command => do
  let range := (← getDeclarationRange? (← getRef)).get!
  modifyEnv fun env => addMainModuleBlueprintEntry env {
    data := .includeLibrary lib.getId
    declarationRange := range
  }

elab "blueprint_include_node" decl:ident : command => do
  let env ← getEnv
  let name ← Command.liftCoreM <| realizeGlobalConstNoOverloadWithInfo decl
  match blueprintExt.find? env name with
  | none => throwError "{name} does not have attribute `[blueprint]`"
  | some node =>
    let range := (← getDeclarationRange? (← getRef)).get!
    modifyEnv fun env => addMainModuleBlueprintEntry env {
      data := .node node
      declarationRange := range
    }

deriving instance Repr for ModuleDoc in
/-- The export blueprint LaTeX from a module is determined by the list of `BlueprintContent`
in the module. This is analogous to doc-gen4's `ModuleMember`. -/
inductive BlueprintContent where
  | entry : BlueprintEntry → BlueprintContent
  | modDoc : ModuleDoc → BlueprintContent
deriving Inhabited, Repr

def BlueprintContent.declarationRange : BlueprintContent → DeclarationRange
  | .entry i => i.declarationRange
  | .modDoc doc => doc.declarationRange

/--
An order for blueprint contents, based on their declaration range.
-/
def BlueprintContent.order (l r : BlueprintContent) : Bool :=
  Position.lt l.declarationRange.pos r.declarationRange.pos

/-- Get blueprint contents of the current module (this is for debugging). -/
def getMainModuleBlueprintContents (env : Environment) : Array BlueprintContent :=
  let entries := getMainModuleBlueprintEntry env |>.map BlueprintContent.entry
  let modDocs := getMainModuleDoc env |>.map BlueprintContent.modDoc
  (entries ++ modDocs).toArray.qsort BlueprintContent.order

/-- Get blueprint contents of an imported module (this is for debugging). -/
def getBlueprintContents (env : Environment) (module : Name) : Array BlueprintContent :=
  let entries := getBlueprintEntry? env module |>.getD #[] |>.map BlueprintContent.entry
  let modDocs := getModuleDoc? env module |>.getD #[] |>.map BlueprintContent.modDoc
  (entries ++ modDocs).qsort BlueprintContent.order

end BlueprintGen
