import BlueprintGen


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

/-- For any natural numbers $a, b$, $(a + 1) + b = (a + b) + 1$. -/
@[blueprint]
theorem succ_add (a b : MyNat) : add (succ a) b = succ (add a b) := by
  /-- Proof by induction on `b`. -/
  -- If the proof contains sorry, the `\leanok` command will not be added
  sorry

/-- For any natural numbers $a, b$, $a + b = b + a$. -/
@[blueprint]
theorem add_comm (a b : MyNat) : add a b = add b a := by
  induction b with
  | zero =>
    have := trivial
    -- The inline code `abc` is converted to \ref{abc} if possible.
    /-- The base case follows from `MyNat.zero_add`. -/
    simp [add]
  | succ b ih =>
    /-- The inductive case follows from `MyNat.succ_add`. -/
    using succ_add  -- the `using` tactic declares that the proof uses succ_add
    sorry

/-! ## Multiplication -/

/-- Natural number multiplication. -/
@[blueprint (uses := [add])]  -- You may override the inferred statement dependencies by `uses`.
def mul (a b : MyNat) : MyNat := sorry

/-- For any natural numbers $a, b$, $a * b = b * a$. -/
@[blueprint]
theorem mul_comm (a b : MyNat) : mul a b = mul b a := by sorry

/-! ## Fermat's Last Theorem -/

/-- Fermat's last theorem. -/
@[blueprint "Taylor--Wiles"
  -- You may override the inferred statement dependencies by `uses`.
  (uses := [mul])
  -- Alternatively to docstring tactics and `using` tactics, proof metadata can be specified
  -- by `proof` and `proofUses`.
  (proof := /-- See [Wiles1995, Taylor-Wiles1995]. -/) (proofUses := [mul_comm])
  (notReady := true) (discussion := 1)]
theorem flt : (sorry : Prop) := sorry

end MyNat

/-!

In the docstring, usual Markdown features and math mode are supported (by MD4Lean),
with additional support for citations like [Wiles1995] using `[square brackets]`
and references to other nodes like `MyNat.zero_add` using inline `` `code` ``.

You can also directly input raw LaTeX, e.g. as follows:

\begin{thebibliography}{9}

\bibitem{Wiles1995}
Andrew Wiles (1995) \emph{Modular elliptic curves and Fermat's last theorem}, Annals of Mathematics, 141(3), 443--551.

\bibitem{Taylor-Wiles1995}
Richard Taylor and Andrew Wiles (1995) \emph{Ring-theoretic properties of certain Hecke algebras}, Annals of Mathematics, 141(3), 553--572.

\end{thebibliography}

-/

-- Finally, these are utility commands for debugging:

#show_blueprint BlueprintGen.Content
#show_blueprint
#show_blueprint_json
