function setup(::Val{:robust_avoid_simple}; T=1,
                 num_obj=1,
                 num_obj_faces=4,
                 obstacle_spacing = 1.0,
                 exploration_vertices=10,
                 num_projections=5,
                 lane_heading = 0.0,
                 initial_speed=3.0,
                 lane_width = 10.0,
                 initial_box_length = 6.0,
                 lane_dist_incentive = 10.0,
                 max_accel = 10.0,
                 kwargs...)

    # Ego poly: x1ₜ[1:2] + { z : Aₑz + bₑ ≥ 0 }
    # Obj poly: x2ₜ[1:2] + { z : Aₒz + bₒ ≥ 0 }
    
    Q = [1.0 0 0 0 ;
         0 1 0 0;
         0 0 0 0;
         0 0 0 0]
    R = [0.1 0;
         0 0.1]
    q = [0.0, 0, 0, 0]

    Aₑ = [1.0 0;
          0 1;
          -1 0;
          0 -1]
    bₑ = ones(4)

    a2 = [sqrt(3), -1]
    a2 = a2 / norm(a2)
    a3 = [-sqrt(3), -1]
    a3 = a3 / norm(a3)

    Aₒ = [1.0 0;
          a2'
          a3']
    bₒ = ones(3)

    x1 = QPN.variables(:x1, 1:4, 1:T)  
    x2 = QPN.variables(:x2, 1:4, 1:T)

    u1 = QPN.variables(:u1, 1:2, 1:T)
    u2 = QPN.variables(:u2, 1:2, 1:T)
    x̄1 = QPN.variables(:x̄1, 1:4)
    x̄2 = QPN.variables(:x̄2, 1:4)

    s = QPN.variables(:s, 1:2, 1:T)
    ϵ = QPN.variables(:ϵ, 1:T)
 
    qp_net = QPNet(x1,x2,u1,u2,x̄1,x̄2,s,ϵ)
 
   
    #####################################################################
    
    # Add players responsible for identifying least-violated obstacle halfspace
    # constraint (min s s.t. s ≥ (aᵢ'x - bᵢ)) 
    # [recall obstacle avoidance ⇿ ∃ i s.t. aᵢ'x > bᵢ, i.e. only one halfspace
    # constraint needs to be satisfied to "avoid" the obstacle]
    
    s_players = Dict()

    for t = 1:T
        cost = ϵ[t]
        cons = [Aₑ*(s[:,t]+x1[1:2,t]) + ones(4)*ϵ[t]; Aₒ*(s[:,t]+x2[1:2,t]) + ones(3)*ϵ[t]]
        lb = fill(0.0, length(cons))
        ub = fill(Inf, length(cons))
        con_id = QPN.add_constraint!(qp_net, cons, lb, ub)
        vars = [s[:,t]; ϵ[t]]
        s_players[t] = QPN.add_qp!(qp_net, cost, [con_id,], vars...)
    end
  
    # Adversary
    dynamic_cons = []
    control_cons = []
    for t = 1:T
        if t==1
            append!(dynamic_cons, x2[:, t] - dyn(x̄2, u2[:, t]))
        else
            append!(dynamic_cons, x2[:, t] - dyn(x2[:, t-1], u2[:, t]))
        end
        append!(control_cons, u2[:,t])
    end
    lb_dyn = fill(0.0, length(dynamic_cons))
    ub_dyn = fill(0.0, length(dynamic_cons))
    lb_control = fill(-1.0, length(control_cons))
    ub_control = fill(+1.0, length(control_cons))
    ad_con_id = QPN.add_constraint!(qp_net, [dynamic_cons; control_cons], [lb_dyn; lb_control], [ub_dyn; ub_control])
    cost = sum(ϵ)
    ad_player = QPN.add_qp!(qp_net, cost, [ad_con_id], x2, u2)

    # Ego
    dynamic_cons = []
    control_cons = []
    for t = 1:T
        if t==1
            append!(dynamic_cons, x1[:, t] - dyn(x̄1, u1[:, t]))
        else
            append!(dynamic_cons, x1[:, t] - dyn(x1[:, t-1], u1[:, t]))
        end
        append!(control_cons, u1[:,t])
    end
    lb_dyn = fill(0.0, length(dynamic_cons))
    ub_dyn = fill(0.0, length(dynamic_cons))
    lb_control = fill(-10.0, length(control_cons))
    ub_control = fill(+10.0, length(control_cons))
    ego_con_id = QPN.add_constraint!(qp_net, [dynamic_cons; control_cons], [lb_dyn; lb_control], [ub_dyn; ub_control])
    cost = sum(0.5*x1[:,t]'*Q*x1[:,t] + x1[:,t]'*q + 0.5*u1[:,t]'R*u1[:,t] for t in 1:T)
    ego_player = QPN.add_qp!(qp_net, cost, [ego_con_id], x1, u1)

    #################
    # Add edges
    edge_list = [(ego_player, ad_player); [(ad_player, s_player) for s_player in values(s_players)]]
    
    QPN.add_edges!(qp_net, edge_list)
    QPN.assign_constraint_groups!(qp_net)
    QPN.set_options!(qp_net; exploration_vertices=exploration_vertices, num_projections=num_projections, kwargs...)
    
    qp_net
end
