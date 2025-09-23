import Lake
open System Lake DSL

package «blueprint-gen»

lean_lib BlueprintGen

lean_lib Example

@[default_target]
lean_exe «blueprint-gen» where
  root := `Main
  supportInterpreter := true

/-- Utility script used for converting from existing blueprint format. -/
lean_exe add_position_info where
  root := `scripts.convert.add_position_info
  supportInterpreter := true

require batteries from git
  "https://github.com/leanprover-community/batteries" @ "v4.23.0-rc2"

require MD4Lean from git
  "https://github.com/acmepjz/md4lean" @ "main"

require Cli from git
  "https://github.com/mhuisi/lean4-cli" @ "v4.23.0-rc2"

/-- A facet to generate the blueprint for a module. -/
module_facet blueprint (mod : Module) : Unit := do
  let exeJob ← «blueprint-gen».fetch
  let modJob ← mod.leanArts.fetch
  let buildDir := (← getRootPackage).buildDir
  let latexFile := mod.filePath (buildDir / "blueprint" / "module") "tex"
  exeJob.bindM fun exeFile => do
    modJob.mapM fun _ => do
      buildFileUnlessUpToDate' latexFile do
        proc {
          cmd := exeFile.toString
          args := #["single", "--build", buildDir.toString, mod.name.toString]
          env := ← getAugmentedEnv
        }

/-- A facet to generate JSON data of blueprint for a module. -/
module_facet blueprintJson (mod : Module) : Unit := do
  let exeJob ← «blueprint-gen».fetch
  let modJob ← mod.leanArts.fetch
  let buildDir := (← getRootPackage).buildDir
  let latexFile := mod.filePath (buildDir / "blueprint" / "module") "json"
  exeJob.bindM fun exeFile => do
    modJob.mapM fun _ => do
      buildFileUnlessUpToDate' latexFile do
        proc {
          cmd := exeFile.toString
          args := #["single", "--json", "--build", buildDir.toString, mod.name.toString]
          env := ← getAugmentedEnv
        }

/-- A facet to generate the blueprint for a library. -/
library_facet blueprint (lib : LeanLib) : Unit := do
  let mods ← (← lib.modules.fetch).await
  let moduleJobs := Job.collectArray <| ← mods.mapM (fetch <| ·.facet `blueprint)
  let exeJob ← «blueprint-gen».fetch
  let buildDir := (← getRootPackage).buildDir
  let latexFile := buildDir / "blueprint" / "library" / lib.name.toString |>.addExtension "tex"
  exeJob.bindM fun exeFile => do
    moduleJobs.mapM fun _ => do
      buildFileUnlessUpToDate' latexFile do
        logInfo "Blueprint indexing"
        proc {
          cmd := exeFile.toString
          args := #["index", "--build", buildDir.toString, lib.name.toString, ",".intercalate (mods.map (·.name.toString)).toList]
          env := ← getAugmentedEnv
        }

/-- A facet to generate the JSON data for the blueprint for a library. -/
library_facet blueprintJson (lib : LeanLib) : Unit := do
  let mods ← (← lib.modules.fetch).await
  let moduleJobs := Job.collectArray <| ← mods.mapM (fetch <| ·.facet `blueprintJson)
  let exeJob ← «blueprint-gen».fetch
  let buildDir := (← getRootPackage).buildDir
  let latexFile := buildDir / "blueprint" / "library" / lib.name.toString |>.addExtension "json"
  exeJob.bindM fun exeFile => do
    moduleJobs.mapM fun _ => do
      buildFileUnlessUpToDate' latexFile do
        logInfo "Blueprint indexing"
        proc {
          cmd := exeFile.toString
          args := #["index", "--json", "--build", buildDir.toString, lib.name.toString, ",".intercalate (mods.map (·.name.toString)).toList]
          env := ← getAugmentedEnv
        }

/-- A facet to generate the blueprint for each library in a package. -/
package_facet blueprint (pkg : Package) : Unit := do
  let libJobs := Job.collectArray <| ← pkg.leanLibs.mapM (fetch <| ·.facet `blueprint)
  let _ ← libJobs.await
  return .nil

/-- A facet to generate the blueprint JSON data for each library in a package. -/
package_facet blueprintJson (pkg : Package) : Unit := do
  let libJobs := Job.collectArray <| ← pkg.leanLibs.mapM (fetch <| ·.facet `blueprintJson)
  let _ ← libJobs.await
  return .nil
