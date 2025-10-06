import Lake
open System Lake DSL

package «blueprint-gen»

lean_lib BlueprintGen

@[default_target]
lean_exe «blueprint-gen» where
  root := `Main
  supportInterpreter := true

/-- Utility script used for converting from existing blueprint format. -/
lean_exe add_position_info where
  root := `scripts.convert.add_position_info
  supportInterpreter := true

require batteries from git
  "https://github.com/leanprover-community/batteries" @ "v4.24.0-rc1"

require MD4Lean from git
  "https://github.com/acmepjz/md4lean" @ "main"

require Cli from git
  "https://github.com/mhuisi/lean4-cli" @ "v4.24.0-rc1"

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

open IO.Process in
/-- Run a command, print all outputs, and throw an error if it fails. -/
private def runCmd (cmd : String) (args : Array String) : ScriptM Unit := do
  let child ← spawn { cmd, args, stdout := .inherit, stderr := .inherit, stdin := .null }
  let exitCode ← child.wait
  if exitCode != 0 then
    throw <| IO.userError s!"Error running command {cmd} {args.toList}"

/-- A script to convert an existing blueprint to blueprint-gen format,
modifying the Lean and LaTeX source files in place. -/
script blueprintConvert (args : List String) do
  let blueprintGen ← BlueprintGen.get
  let convertScript := blueprintGen.srcDir / "scripts" / "convert" / "main.py"
  let libs := (← getRootPackage).leanLibs
  let rootMods := libs.flatMap (·.rootModules)
  if h : rootMods.size = 0 then
    IO.eprintln "No root modules found for any library"
    return 1
  else  -- this else is needed for rootMods[0] to work
  for lib in libs do
    runCmd (← getLake).toString #["build", lib.name.toString]
  IO.eprintln "Calling Python script to convert blueprint to blueprint-gen format"
  runCmd "python3" <| #[
    convertScript.toString] ++
    #["--modules"] ++ rootMods.map (·.name.toString) ++
    #["--root_file", rootMods[0].leanFile.toString] ++
    args
  return 0
