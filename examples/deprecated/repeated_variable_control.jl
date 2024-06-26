"""
variables := x ∈ ℝⁿ, s ∈ ℝ²


min_x f(x)
s.t. l ≤ Ax ≤ u

Reformulated as 

min_{x,s} f(x)
s.t. x,s ∈ argmin 0.5 s²
            s.t. 0 ≤ (Ax-l)ᵢ - s₁ ∀ i 
                 0 ≤ (u-Ax)ᵢ - s₂ ∀ i

"""
function setup(::Val{:repeated_variable_control}; rng=MersenneTwister(1), n=3, m=2, kwargs...)
 
    x = QPN.variables(:x, 1:n) 
    s = QPN.variable(:s)

    Q = sprandn(rng, n, n, 0.3)
    Q = Q'*Q
    q = randn(rng, n)

    A = sprandn(rng, m, n, 0.3)
    l = fill(-1.0, m)
    u = fill( 1.0, m)
 
    qpn = QPNet(x,s)
  
    lb = fill(0.0, 2*m)
    ub = fill(Inf, 2*m)
    cons = [A*x - l; u - A*x] .+ s
    con_id = QPN.add_constraint!(qpn, cons, lb, ub)
    cost = 0.5*s*s
    level = 2
    QPN.add_qp!(qpn, level, cost, [con_id,], x, s)

    cost = 0.5*x'*Q*x + x'*q
    level = 1
    QPN.add_qp!(qpn, level, cost, [])
    
    QPN.assign_constraint_groups!(qpn)
    QPN.set_options!(qpn; kwargs...)

    (; qpn, A, l, u, Q, q)
end

