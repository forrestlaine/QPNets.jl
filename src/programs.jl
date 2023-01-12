struct Quadratic <: Function
    Q::SparseMatrixCSC{Float64, Int32}
    q::Vector{Float64}
end

function (f::Quadratic)(x::Vector{Float64})
    0.5*x'*(f.Q*x + f.q)
end

function Base.sum(fs::Union{Vector{Quadratic}, NTuple{N,Quadratic}}) where N
    Quadratic(sum(f.Q for f in fs), sum(f.q for f in fs)) 
end

struct QP
    f::Quadratic
    S::Dict{Int, Float64}
    indices::Vector{Int}
end

struct QEP
    qps::Dict{Int, QP}
    sets::Dict{Int, Poly}
end

@enum SharedVariableMode begin
    MIN_NORM = 1
    SHARED_DUAL = 2
end

Base.@kwdef struct QPNetOptions
    shared_variable_mode::SharedVariableMode=SHARED_DUAL
    max_iters::Int=150
    tol::Float64=1e-4
    high_dimension::Bool=true
    high_dimension_max_iters::Int=10
    debug::Bool=false
    gen_solution_map::Bool=false
end

struct QPNet
    qps::Dict{Int, QP}
    sets::Dict{Int, Poly}
    network::Vector{Set{Int}}
    options::QPNetOptions
    #QPNet(qps, sets, network) = begin
    #    new(qps, sets, network, QPNetOptions())
    #end
end

function num_levels(qpn::QPNet)
    length(qpn.network)
end

function gather(qpn::QPNet, level)
    qps = Dict(i=>qpn.qps[i] for i in qpn.network[level])
    sets = Dict{Int, Poly}(id=>qpn.sets[id] for qp in values(qps) for id in keys(qp.S))
    QEP(qps, sets)
end

function fair_obj(qep::QEP)
    sum([qp.f for qp in values(qep.qps)])
end

function fair_obj(qpn::QPNet, level)
    sum([qpn.qps[i].f for i in qpn.network[level]])
end

function sub_indices(qpn::QPNet, level)
    L = length(qpn.network)
    reduce(vcat, (qpn.qps[i].indices for l in level+1:L for i in qpn.network[l]))
end

function subeq_indices(qpn::QPNet, level)
    L = length(qpn.network)
    reduce(vcat, (qpn.qps[i].indices for l in level:L for i in qpn.network[l]))
end

function param_indices(qpn::QPNet, level)
    collect(setdiff(1:embedded_dim(first(qpn.sets).second), Set(subeq_indices(qpn, level))))
end
