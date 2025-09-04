# blueprint-gen

This is a quick demo for a new blueprint tool for Lean. It is currently completely in proof-of-concept stage.

The blueprint LaTeX (and PDF and web) is generated from the source Lean code directly,
where the nodes are declared by the `blueprint` attribute:

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

/-- For any natural number $a$, $0 + a = a$. -/
@[blueprint, simp]
theorem zero_add (a : MyNat) : add zero a = a := by
  /-- The proof follows by induction. -/
  induction a <;> simp [*, add]

end MyNat
```

becomes

```latex
# Natural numbers

\begin{definition}[Natural numbers]\leanok{}\lean{MyNat}\label{MyNat}
% at ./Example.lean:6.0-9.24
\end{definition}

## Addition
Here we define addition of natural numbers.


\begin{definition}\leanok{}\uses{MyNat}Natural number addition.\lean{MyNat.add}\label{MyNat.add}
% at ./Example.lean:18.0-23.28
\end{definition}

\begin{theorem}\leanok{}\uses{MyNat,MyNat.add}For any natural number $a$, $0 + a = a$.\lean{MyNat.zero_add}\label{MyNat.zero_add}
% at ./Example.lean:25.0-29.31
\end{theorem}

\begin{proof}\leanok{}The proof follows by induction.\end{proof}
```

This tool is built directly on top of [leanblueprint](https://github.com/PatrickMassot/leanblueprint).

Some features that are available:

- You can declare the informal statement of a theorem or definition with its docstring.
- You can declare the informal proof of a theorem with the `/-- proof -/` tactic.
- The dependencies of a theorem statement and proof are automatically inferred.
  You can override this with the `uses` and `proofUses` options,
  and with the `using` tactic.
- Whether the statement or proof is ready (i.e. `\leanok`) is inferred from whether it is
  sorry-free.
- You can manually insert nodes from other modules to the blueprint with the
  `blueprint_input_node node_from_other_module` command.
- For debugging, you can use the `#show_blueprint` and `#show_blueprint_json` commands.

See [Example.lean](./Example.lean) for more details.

## Demo

To run the demo [Example.lean](./Example.lean), run:

```sh
lake build Example:blueprint
```

Then the generated blueprint will be in `.lake/build/blueprint/module/Example.tex`.
I have already manually `\input` this file into [blueprint/src/content.tex](./blueprint/src/content.tex), so that you can then run:

```sh
leanblueprint pdf  # to generate the PDF
leanblueprint web  # to generate the web HTML
leanblueprint serve  # to serve the web HTML
```

(where `leanblueprint` is from [leanblueprint](https://github.com/PatrickMassot/leanblueprint)).

Then you can go to `http://0.0.0.0:8080` to see the web version or `http://0.0.0.0:8080/dep_graph_document.html` to see the dependency graph.
