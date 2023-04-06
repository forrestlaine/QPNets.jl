function solve(qpn::QPNet, x_init; 
        level=1,
        rng=MersenneTwister())

    if level == num_levels(qpn)
        start = time()
        qep = gather(qpn, level)
        (; x_opt, Sol) = solve_qep(qep, x_init; 
                                   level,
                                   qpn.options.debug, 
                                   qpn.options.high_dimension, 
                                   qpn.options.shared_variable_mode, 
                                   rng)
        fin = time()
        qpn.options.debug && println("Level ", level, " took ", fin-start, " seconds.")
        qpn.options.debug && display_debug(level, 1, x_opt, nothing, nothing)
        return (; x_opt, Sol)
    else
        x = copy(x_init)
        fair_objective = fair_obj(qpn, level) # TODO should fair_objective still be used for all shared_var modes?
        qep = gather(qpn, level)
        level_constraint_ids = vcat(([id for qp in values(qep.qps) if id ∈ qp.constraint_indices] for id in keys(qep.constraints))...)
        sub_inds = sub_indices(qpn, level)

        for iters in 1:qpn.options.max_iters
            ret_low = solve(qpn, x; level=level+1, rng)
            x_low = ret_low.x_opt
            Sol_low = ret_low.Sol

            set_guide!(Sol_low, fair_objective)
            start = time()
            local_xs = []
            local_solutions = [] #Vector{LocalAVISolutions}()
            local_regions = Vector{Poly}()
            all_same = true
            low_feasible = false
            current_fair_value = fair_objective(x)
            current_infeasible = !all( x ∈ qep.constraints[i].poly for i in level_constraint_ids)
            sub_count = 0
            throw_count = 0
            if qpn.options.debug && level+1 < num_levels(qpn)
                println("About to reason about potentially ", 
                        potential_length(Sol_low), " pieces (depth of ", depth(Sol_low), ").")
            end    
            local S_keep
            for (e, S) in enumerate(distinct(Sol_low))
                sub_count += 1
                S_keep = simplify(S)
                low_feasible |= (x ∈ S_keep)
                res = solve_qep(qep, x, S_keep, sub_inds;
                                level,
                                qpn.options.debug,
                                qpn.options.high_dimension,
                                qpn.options.shared_variable_mode,
                                rng)
                set_guide!(res.Sol, z->(z-x)'*(z-x))
                new_fair_value = fair_objective(res.x_opt) # caution using fair_value
                better_value_found = new_fair_value < current_fair_value - qpn.options.tol
                same_value_found = new_fair_value < current_fair_value + qpn.options.tol
                current_agrees_with_piece = any(S -> x ∈ S, res.Sol)
                if current_infeasible || better_value_found
                    diff = norm(x-res.x_opt)
                    qpn.options.debug && println("Diff :", diff)
                    x .= res.x_opt
                    all_same = false #TODO should queue all non-solutions?
                    break
                elseif current_agrees_with_piece || same_value_found
                    # assumption here is that if solution has same value (for
                    # fair objective(is this right for games?)) then valid
                    # piece. Warning: These pieces may then be NON-LOCAL.
                    # Needed for some problems (e.g. pessimistic
                    # committment).
                    push!(local_xs, res.x_opt)
                    push!(local_solutions, res.Sol)
                    push!(local_regions, S_keep)
                else # poor-valued neighbor
                    throw_count += 1
                    continue
                end
            end

            if !current_infeasible && !low_feasible
                res = solve_qep(qep, x, S_keep, sub_inds; qpn.options.high_dimension)
                diff = norm(x-res.x_opt)
                qpn.options.debug && println("Diff :", diff)
                x .= res.x_opt
                all_same = false
            end
            fin = time()
            qpn.options.debug && println("Level ", level, " took ", fin-start, " seconds.") 
            qpn.options.debug && display_debug(level, iters, x, sub_count, throw_count)

            if qpn.options.high_dimension 
                if level == 1 && iters < qpn.options.high_dimension_max_iters || !all_same
                    continue
                end
            else
                if !all_same
                    continue
                end
            end

            level_dim = length(param_indices(qpn, level))
            S = (qpn.options.gen_solution_map || level > 1) ? combine(local_regions, local_solutions, level_dim; show_progress=true) : nothing
            # TODO is it needed to specify which subpieces constituted S, and check
            # consistency in up-network solves?
            return (; x_opt=x, Sol=S)
        end
        error("Can't find solution.")
    end
end

"""
Conustructs the solution set
S := ⋃ₚ ⋂ᵢ Zᵢᵖ

Zᵢᵖ ∈ { Rᵢ', Sᵢ }
where Rᵢ' is the set complement of Rᵢ.
"""
function combine(regions, solutions, level_dim; show_progress=false)
    if length(solutions) == 0
        @error "No solutions to combine..."
    elseif length(solutions) == 1
        first(solutions)
    else
        complements = map(complement, regions)
        combined = [[collect(s); rc] for (rc, s) in zip(complements, solutions)]
        IntersectionRoot(combined, length.(complements), level_dim; show_progress)
    end
end
