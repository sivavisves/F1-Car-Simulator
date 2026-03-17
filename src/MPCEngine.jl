# MPCEngine.jl
# Core solver that calculates optimal deployment trajectory (QP or LP)

using JuMP
using HiGHS

struct MPCSolver
    model::Model
    config::Dict{Symbol, Any}
end

function setup_solver(horizon::Int, track::TrackMap, initial_soc::Float64, defend_reserve::Float64)
    # Using Gurobi as the selected high-performance solver
    # This acts as an LP/QP solver
    model = Model(HiGHS.Optimizer)
    set_silent(model)
    
    # 2026 Regulation Parameters
    MAX_SOC = 4.0 # MJ
    M_J_PER_LAP = 9.0 # MJ total deployment allowed per lap
    MAX_POWER = 350.0 # kW override limits
    
    # Variables
    # u_k: Deployment at each track node over the horizon
    @variable(model, 0 <= u[1:horizon] <= MAX_POWER)
    # soc_k: State of charge at the start of each segment
    @variable(model, 0 <= soc[1:horizon+1] <= MAX_SOC)
    
    # Initial Condition
    @constraint(model, soc[1] == initial_soc)
    
    # Dynamics and Constraints
    @constraint(model, soc_dyn[k=1:horizon], soc[k+1] == soc[k] - (u[k] * (track.nodes[k].length / track.nodes[k].speed_estimate)) / 1000.0)
    
    # Operating Reserve (Defend condition)
    @constraint(model, soc[horizon+1] >= defend_reserve)
    
    # Regulatory 9MJ limit (for simplicity we enforce over the horizon)
    @constraint(model, sum((u[k] * (track.nodes[k].length / track.nodes[k].speed_estimate)) / 1000.0 for k in 1:horizon) <= M_J_PER_LAP)
    
    # Objective: Maximize locational marginal value of deployment minus penalties
    # Linear objective -> makes it an LP (Fastest solver performance)
    # Tuned terminal SOC weight to 150.0. This is strategically between the value of 
    # Node 1 (133.3) and Node 9 (184.0), tricking the short-horizon MPC to save energy for Node 9 next lap!
    @objective(model, Max, sum(track.nodes[k].marginal_value * u[k] for k in 1:horizon) + 150.0 * soc[horizon+1])
    
    return MPCSolver(model, Dict(:horizon => horizon))
end

function optimize_deployment!(solver::MPCSolver; time_limit_ms=100)
    # Enforce 10Hz/100ms real-time limit for edge-compute
    set_time_limit_sec(solver.model, time_limit_ms / 1000.0)
    
    optimize!(solver.model)
    
    # Extract deployment policy and duals
    if termination_status(solver.model) == MOI.OPTIMAL
        u_opt = value.(solver.model[:u])
        soc_opt = value.(solver.model[:soc])
        # Dual variables represent the shadow price
        lambda_soc = dual.(solver.model[:soc_dyn])
        return u_opt, lambda_soc
    else
        # Sub-optimal or failed convergence
        return zeros(solver.config[:horizon]), zeros(solver.config[:horizon] + 1)
    end
end
