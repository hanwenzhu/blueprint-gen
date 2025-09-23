# blueprint-gen

*This is a quick demo for a new blueprint tool for Lean. It is currently completely in proof-of-concept stage.*

Blueprint-gen is a tool for generating the blueprint data of a Lean project directly from Lean.

The blueprint is a high-level plan of a Lean project, consisting of a series of nodes (theorems and definitions) and the dependency relations between them.
The purpose of blueprint-gen is to make it easier to write the blueprint by directly referencing nodes in Lean.

Nodes are declared in Lean by the `@[blueprint]` tag.
In the blueprint LaTeX, you may input these nodes using the `\inputleannode{name}` command,
or input entire modules using the `\inputleanmodule{Module}` command.

This tool is built directly on top of [leanblueprint](https://github.com/PatrickMassot/leanblueprint).

## Example

Consider the following `MyNat` API:

```lean
/-! # Natural numbers -/

@[blueprint "Natural numbers"]
inductive MyNat : Type where
  | zero : MyNat
  | succ : MyNat → MyNat

namespace MyNat

/-!
## Addition
Here we define addition of natural numbers.
-/

/-- Natural number addition. -/
@[blueprint]
def add (a b : MyNat) : MyNat :=
  match b with
  | zero => a
  | succ b => succ (add a b)

/-- For any natural number $a$, $0 + a = a$, where $+$ is Def. `MyNat.add`. -/
@[blueprint, simp]
theorem zero_add (a : MyNat) : add zero a = a := by
  /-- The proof follows by induction. -/
  induction a <;> simp [*, add]

end MyNat
```

The output of the above example is in [blueprint/src/print.pdf](./blueprint/src/print.pdf).

## Specifying the blueprint

After tagging with `@[blueprint]`, blueprint-gen will:

1. Extract the statement and proof of a node from docstrings.
2. Infer the dependencies of a node from the constants used in the statement or proof.
3. Infer whether the statement or proof is ready (i.e. `\leanok`) from whether it is sorry-free.
4. Add the node to the generated blueprint.

You may override the constants used in the statement or proof with the `uses` and `proofUses` options, or with the `using` tactic.

## Generating the blueprint

First, install [leanblueprint](https://github.com/PatrickMassot/leanblueprint) and follow the instructions there to set up a blueprint project, if not already done.

To generate the blueprint for a module, first input the generated blueprint to the blueprint document:

```latex
% Typically, in blueprint/src/content.tex

\input{../../.lake/build/blueprint/library/Example}

% Input the blueprint contents of module `Example`:
\inputleanmodule{Example}

% You may also input only a single node using \inputleannode{MyNat.add}.
```

Then run:

```sh
# Generate the blueprint to .lake/build/blueprint
lake build :blueprint
# Build the blueprint using leanblueprint
leanblueprint pdf
leanblueprint web
```

You may also want to put `lake build :blueprint` in the GitHub Actions workflow typically at `.github/workflows/blueprint.yml`.

## Converting from existing blueprint format

With a project that uses the existing leanblueprint format:

First go to a clean branch without any uncomitted changes, to prevent overwriting any work you have done.

You can then convert to blueprint-gen format by adding `blueprint-gen` as a dependency to lakefile, run `lake update blueprint-gen`, and then run:

```sh
# TODO, make this into lake exe
# At the project root
python .lake/packages/blueprint-gen/scripts/convert/main.py --modules {root modules of your project}
```

Then you would need to fix the errors in the converted files. You would also need to manually add the nodes that are not in the project itself (typically, `\mathlibok` nodes) to the blueprint, which will be saved to `extra_nodes.lean`.
