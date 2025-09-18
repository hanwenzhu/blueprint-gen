import BlueprintGen.Load
import Cli


open Lean

/-! This file contains utilities for porting from an existing LaTeX blueprint. -/

-- TODO: Do parsing; don't do ntp-toolkit style
-- Reasons;
-- 1. Python string parsing is easy to modify and extend
-- 2. For converted nodes, don't really need to put docstrings, infer uses (just use statement :=, uses :=, etc)
-- 3. Any Lean-heavy (e.g. ntp-toolkit) need maintenance & version control to keep ahead of breaking changes

-- Route:
-- Python parses blueprint
-- Python calls Lean code (lake env lean) with this script but with an extra import (e.g. import FLT)
-- This script converts Node in JSON stdin to NodeWithPos in JSON stdout
-- Python modifies files by the Pos

-- For the original blueprint, define "header" latex files where
-- nodes are defined but not input, and then in human-written blueprint
-- just use \inputnode{...} to include

open Lean Cli BlueprintGen

def runAddPositionInfo (p : Parsed) : IO UInt32 := do
  let some imports := p.flag? "imports" |>.bind (·.as? (Array ModuleName))
    | IO.throwServerError "--imports flag is required"
  let stdin ← IO.getStdin
  let input ← stdin.readToEnd
  let json ← IO.ofExcept (Json.parse input)
  let nodes : Array Node ← IO.ofExcept (fromJson? json)
  runEnvOfImports imports do
    let nodesWithPos ← nodes.mapM fun node => node.toNodeWithPos
    IO.println (nodesWithPos.map NodeWithPos.toJson |>.toJson)
  return 0

def addPositionInfoCmd : Cmd := `[Cli|
  add_position_info VIA runAddPositionInfo;
  "Add position information to a JSON list of nodes."

  FLAGS:
    imports : Array ModuleName; "Comma-separated Lean modules to import."
]

def main (args : List String) : IO UInt32 := do
  addPositionInfoCmd.validate args
