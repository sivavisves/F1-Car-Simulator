# HMI_Logic.jl
# Translates dual variables (shadow prices) into actionable driver HMI signals

function calculate_hmi_signals(marginal_value::Float64, shadow_price::Float64, current_soc::Float64, duration::Float64)
    # Shadow price (\lambda) represents the marginal cost of 1 MJ of SOC.
    # Deploying 1 kW for 'duration' seconds consumes (duration / 1000.0) MJ.
    # Therefore, the opportunity cost per 1 kW deployed at this node is:
    cost_per_kw = abs(shadow_price) * (duration / 1000.0)
    
    # If Marginal Value is greater than or equal to the cost -> Green
    if marginal_value >= (0.99 * cost_per_kw) && current_soc > 1.0
        return :GREEN # Clearing - hit override
    elseif marginal_value >= (0.8 * cost_per_kw)
        return :YELLOW # Marginal - defend/close gaps
    else
        return :RED # Deficit - harvest mode
    end
end
