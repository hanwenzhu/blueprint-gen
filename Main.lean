import BlueprintGen
import Lean
import Cli

open Lean Cli BlueprintGen

def outputBaseDir (buildDir : System.FilePath) : System.FilePath :=
  buildDir / "blueprint"

def runSingleCmd (p : Parsed) : IO UInt32 := do
  let buildDir := match p.flag? "build" with
    | some dir => dir.as! String
    | none => ".lake/build"
  let baseDir := outputBaseDir buildDir
  let module := p.positionalArg! "module" |>.as! String |>.toName
  let isJson := p.hasFlag "json"
  if isJson then
    let json ← jsonOfImportModule module
    outputJsonResults baseDir module json
  else
    let latex ← latexOfImportModule module
    outputLatexResults baseDir module latex
  return 0

def runIndexCmd (p : Parsed) : IO UInt32 := do
  let buildDir := match p.flag? "build" with
    | some dir => dir.as! String
    | none => ".lake/build"
  let baseDir := outputBaseDir buildDir
  let library := p.positionalArg! "library" |>.as! String |>.toName
  let modules := p.positionalArg! "modules" |>.as! (Array String) |>.map (·.toName)
  let isJson := p.hasFlag "json"
  if isJson then
    outputLibraryJson baseDir library modules
  else
    outputLibraryLatex baseDir library modules
  return 0

def singleCmd := `[Cli|
  single VIA runSingleCmd;
  "Only generate the blueprint for the module it was given, might contain broken \\input{}s unless all blueprint files are generated."

  FLAGS:
    j, json; "Output JSON instead of LaTeX."
    b, build : String; "Build directory."

  ARGS:
    module : String; "The module to generate the blueprint for."
]

def indexCmd := `[Cli|
  index VIA runIndexCmd;
  "Collates the LaTeX outputs of modules in a library from `single` into a LaTeX file with \\input{}s pointing to the modules."

  FLAGS:
    j, json; "Output JSON instead of LaTeX."
    b, build : String; "Build directory."

  ARGS:
    library : String; "The library to index."
    modules : Array String; "The modules in the library."
]

def blueprintCmd : Cmd := `[Cli|
  "blueprint-gen" NOOP;  -- TODO docs
  "A blueprint generator for Lean 4."

  SUBCOMMANDS:
    singleCmd;
    indexCmd
]

def main (args : List String) : IO UInt32 :=
  blueprintCmd.validate args
