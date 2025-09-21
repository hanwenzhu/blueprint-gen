import BlueprintGen.Output


namespace BlueprintGen

/-!
Loading the analysis result of a module.
-/

open Lean

/-- This is copied from `DocGen4.envOfImports`. -/
def envOfImports (imports : Array Name) : IO Environment := do
  -- needed for modules which use syntax registered with `initialize add_parser_alias ..`
  unsafe Lean.enableInitializersExecution
  importModules (imports.map (Import.mk · false true false)) Options.empty (leakEnv := true) (loadExts := true)

/-- This is copied from `DocGen4.load`. -/
def runEnvOfImports (imports : Array Name) (x : CoreM α) : IO α := do
  initSearchPath (← findSysroot)
  let env ← envOfImports imports
  let config := {
    -- TODO: parameterize maxHeartbeats
    maxHeartbeats := 100000000,
    options := ⟨[
      (`pp.tagAppFns, true),
      (`pp.funBinderTypes, true),
      (`debug.skipKernelTC, true),
      (`Elab.async, false)
    ]⟩,
    -- TODO: Figure out whether this could cause some bugs
    fileName := default,
    fileMap := default,
  }

  Prod.fst <$> x.toIO config { env }

/-- Outputs the blueprint of a module. -/
def latexOfImportModule (module : Name) : IO Latex :=
  runEnvOfImports #[module] (moduleToLatexHeader module)

/-- Outputs the JSON data for the blueprint of a module. -/
def jsonOfImportModule (module : Name) : IO Json :=
  runEnvOfImports #[module] (moduleToJson module)

end BlueprintGen
