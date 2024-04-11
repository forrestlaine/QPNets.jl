"""
A reactive toll setting problem.
N = number of toll lane entrances/exits
L = number of lanes of traffic (L-1 are toll lanes)
0 ≤ p0 ≤ 1 : fraction of traffic in initial toll lane
0 ≤ p[:, n] ≤ 1 : fraction of traffic in each lane at the n-th stage
0 ≤ T[:, n] : the toll price (in standardized units) for traveling in the toll lanes at the n-th stage.
0 ≤ α : the cost factor for lane change congestion between toll sections
0 ≤ D : the extra price (in standardized units) for traveling in any non-toll lane

function setup(::Val{:repeated_toll_setting}; N=2, L = 3, D=0.0, α=0.2, kwargs...)
    T = QPN.variables(:T, 1:L-1, 1:N)
    P = QPN.variables(:P, 1:L, 1:N)
    P0 = ones(L) ./ L

    qp_net = QPNet(T, P)
   
    running_costs = []
    running_revenues = []

    p_players = Dict()
    t_players = Dict()
    for n = N:-1:1
        pnm1 = n > 1 ? P[:, n-1] : P0
        cons = [P[:, n]; sum(P[:,n])]
        lb = [zeros(L); 1.0]
        ub = [fill(Inf, L); 1.0]
        con_id = QPN.add_constraint!(qp_net, cons, lb, ub)
        lane_costs = [T[:,n]; D] + P[:,n]
        lane_change = (P[:,n]-pnm1)'*(P[:,n]-pnm1)
        cost = P[:,n]'*lane_costs + α*lane_change
        push!(running_costs, cost)
        #p_players[n] = QPN.add_qp!(qp_net, sum(running_costs), [con_id,], P[:,n])
        p_players[n] = QPN.add_qp!(qp_net, cost, [con_id,], P[:,n])

        revenue = -T[:,n]'*P[1:L-1,n]
        cons = T[:,n]
        lb = fill(0.0, L-1)
        ub = fill(Inf, L-1)
        push!(running_revenues, revenue)
        con_id = QPN.add_constraint!(qp_net, cons, lb, ub)
        #t_players[n] = QPN.add_qp!(qp_net, sum(running_revenues), [con_id,], T[:,n])
        t_players[n] = QPN.add_qp!(qp_net, revenue, [con_id,], T[:,n])
    end

    edge_list = []
    for n in 1:N
        push!(edge_list, (t_players[n], p_players[n]))
        if n < N
            push!(edge_list, (p_players[n], t_players[n+1]))
        end
    end
    
    QPN.add_edges!(qp_net, edge_list)
    QPN.assign_constraint_groups!(qp_net)
    QPN.set_options!(qp_net; exploration_vertices=10, check_convexity=true)
    qp_net.default_initialization = [zeros((L-1)*N); fill(1.0/L, L*N)]

    qp_net
end
"""

function traffic_dyn(P, U, PP)
    L = length(P)

    cons = map(1:L) do l
        con = P[l]
        for l1 in (l-1,l+1)
            (1 ≤ l1 ≤ L) || continue
            con -= U[l,l1]
            con += U[l1,l]
        end
        con
    end
    cons - PP
end

function setup(::Val{:repeated_toll_setting}; N=2, L = 3, D=0.0, α=0.2, kwargs...)
    T = QPN.variables(:T, 1:L-1, 1:N)
    P = QPN.variables(:P, 1:L, 1:N)
    U = QPN.variables(:U, 1:2*L-2, 1:N)
    P0 = ones(L) ./ L

    qp_net = QPNet(T, P, U)
   
    running_costs = []
    running_revenues = []
    

    p_players = Dict()
    t_players = Dict()
    for n = N:-1:1
        UU = zeros(eltype(U), L, L)
        ind = 1
        for i in 1:L
            for j in (i-1, i+1)
                (1 ≤ j ≤ L) || continue
                UU[i,j] = U[ind,n]
                ind += 1
            end
        end
        pnm1 = n > 1 ? P[:, n-1] : P0
        dyn_cons = traffic_dyn(pnm1, UU, P[:,n])
        cons = [P[:, n]; sum(P[:,n]); dyn_cons; U[:,n]]
        lb = [zeros(L); 1.0; zeros(length(dyn_cons)); zeros(2*L-2)]
        ub = [fill(Inf, L); 1.0; zeros(length(dyn_cons)); fill(Inf, 2*L-2)]
        con_id = QPN.add_constraint!(qp_net, cons, lb, ub)
        lane_costs = [T[:,n]; D] + P[:,n]
        lane_change = U[:,n]'*U[:,n]
        cost = P[:,n]'*lane_costs + α*lane_change
        push!(running_costs, cost)
        tot_cost = n ≤ N ? cost : sum(running_costs[end-1:end])
        tot_cost = sum(running_costs)
        p_players[n] = QPN.add_qp!(qp_net, tot_cost, [con_id,], P[:,n], U[:,n])
        #p_players[n] = QPN.add_qp!(qp_net, cost, [con_id,], P[:,n], U[:,n])

        revenue = -T[:,n]'*P[1:L-1,n]
        cons = T[:,n]
        lb = fill(0.0, L-1)
        ub = fill(Inf, L-1)
        push!(running_revenues, revenue)
        con_id = QPN.add_constraint!(qp_net, cons, lb, ub)
        t_players[n] = QPN.add_qp!(qp_net, sum(running_revenues), [con_id,], T[:,n])
        #t_players[n] = QPN.add_qp!(qp_net, revenue, [con_id,], T[:,n])
    end

    edge_list = []
    for n in 1:N
        push!(edge_list, (t_players[n], p_players[n]))
        if n < N
            push!(edge_list, (p_players[n], t_players[n+1]))
        end
    end
    
    QPN.add_edges!(qp_net, edge_list)
    QPN.assign_constraint_groups!(qp_net)
    QPN.set_options!(qp_net; exploration_vertices=10, check_convexity=true)
    qp_net.default_initialization = [zeros((L-1)*N); fill(1.0/L, L*N); zeros(N*2*(L-1))]

    qp_net
end
