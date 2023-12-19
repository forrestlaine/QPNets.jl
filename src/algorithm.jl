function solve_base!(qpn::QPNet, x_init, request, relaxable_inds;
        level=1,
        proj_vectors=Vector{Vector{Float64}}(),
        request_comes_from_parent=false,
        rng=MersenneTwister())

    x = copy(x_init)
    if level == 1 && isempty(proj_vectors)
        foreach(i->push!(proj_vectors, randn(rng, length(x))), 1:qpn.options.num_projections)
    end
    for iters in 1:qpn.options.max_iters
        proj_vals = [x'v for v in proj_vectors]
        @info "Iteration $iters at level $level. $proj_vals"
        level == 1 && visualize(qpn, x; T=5)
        
        if level < num_levels(qpn)
            ret_low = solve(qpn, x, request, relaxable_inds; level=level+1, rng, proj_vectors)
            @info "Resuming iteration $iters at level $level"
            S = ret_low.Sol
            x = ret_low.x_opt
        else
            S = Dict()
        end

        players_at_level = qpn.network_depth_map[level] |> collect
        processing_tasks = map(players_at_level) do id
            #Threads.@spawn process_qp(qpn, id, x, S)
            process_qp(qpn, id, x, S; exploration_vertices=qpn.options.exploration_vertices)
        end
        results = fetch.(processing_tasks)
        equilibrium = true
        subpiece_assignments = Dict{Int, Poly}()
        subpiece_ids = Dict{Int, Int}()
        for (i,id) in enumerate(players_at_level)
            r = results[i]
            if !r.solution
                equilibrium = false
                if level < num_levels(qpn)
                    for (child_id,subpiece_id) in r.subpiece_assignments
                        # Even if another player has already indicated that at least
                        # one subpiece for this particular child (which current
                        # player also parents) results in non-equilibrium,
                        # we choose to overwrite with subpiece causing
                        # discontentment for current player.
                        subpiece_assignments[child_id] = S[child_id][subpiece_id]
                        subpiece_ids[child_id] = subpiece_id
                    end
                end
            else
                S[id] = results[i].S |> remove_subsets
                !isnothing(S[id]) && @info "Solution graph for node $i has $(length(S[id])) pieces."
            end
        end
        if !equilibrium
            try
                xnew = solve_qep(qpn, players_at_level, x, subpiece_assignments)
                if norm(xnew-x) < 1e-3
                    @infiltrate
                end
                x = xnew
            catch e
                @error "Solving error when computing equilibrium with subpiece ids: $subpiece_ids. Returning x, although this is a known non-equilibrium."
                return (; x_fail=x)
            end
            continue
        else
            return (; x_opt=x, Sol=S, identified_request=Set{Linear}(), x_alts=Vector{Float64}[])
        end
    end
    error("Can't find solution")
end
