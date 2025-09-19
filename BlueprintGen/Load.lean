import BlueprintGen.Output
import DocGen4.Load


namespace BlueprintGen

/-!
Loading the analysis result of a module.
-/

open Lean

/-- This is copied from `DocGen4.load`. -/
def runEnvOfImports (imports : Array Name) (x : CoreM α) : IO α := do
  initSearchPath (← findSysroot)
  let env ← DocGen4.envOfImports imports
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
  runEnvOfImports #[module] (moduleToLatex module)

/-- Outputs the JSON data for the blueprint of a module. -/
def jsonOfImportModule (module : Name) : IO Json :=
  runEnvOfImports #[module] (moduleToJson module)

end BlueprintGen
