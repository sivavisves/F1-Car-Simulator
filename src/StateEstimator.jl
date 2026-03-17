# StateEstimator.jl
# The "Load Forecast" - estimates opponent SOC

function estimate_opponent!(historical_data::Vector{Float64}, gap_to_opponent::Float64)
    # Simplified estimation based on kinematics
    # Returns an estimated opponent SOC and a necessary defensive reserve requirement.
    
    # Dynamically adjust the defensive reserve to gain a tactical advantage:
    if gap_to_opponent < 0.0
        # Car A is BEHIND (Attacking). We want to use all available energy to catch up.
        # Deplete battery entirely if it yields a faster sector time.
        required_reserve = 0.0
    elseif gap_to_opponent < 1.0
        # Car A is slightly AHEAD, but within DRS threat range (< 1.0s).
        # We need to hold a defensive reserve to counter attacks on long straights.
        # The closer the opponent, the higher the reserve requirement.
        required_reserve = 0.5 + (1.0 - gap_to_opponent) * 1.0 # Scales from 0.5 MJ to 1.5 MJ
    else
        # Car A is safely AHEAD (> 1.0s). No immediate threat.
        # Drop reserve to optimize for pure continuous lap time.
        required_reserve = 0.0
    end
    
    # Cap the reserve so we don't demand more than what's reasonable
    required_reserve = min(required_reserve, 2.0)
    
    # Example estimation (constant for Phase 1 simulation)
    predicted_op_soc = 2.0 # MJ
    
    return predicted_op_soc, required_reserve
end
