# ClosedLoopSim.jl
# Simulates a full 56-lap race at Sepang Circuit: Car A (MPC) vs Car B (Heuristic)

include("../src/ProjectOverbid.jl")
using .ProjectOverbid

function run_race()
    println("==================================================")
    println("🏁 Starting 56-Lap Race at Sepang International Circuit 🏁")
    println("==================================================\n")
    # Initialize Track
    # The MPC prediction horizon must cover the longest straight (Node 9 is 900m)
    # and we want to optimize over at least one full lap boundary.
    track = load_sepang_track()
    horizon = length(track.nodes) # Currently 10 nodes
    
    # Base lap time calculation (simplistic kinematic, no deployment)
    base_lap_time = sum(n.length / n.speed_estimate for n in track.nodes)
    
    # Start conditions: Max SOC 4.0 MJ
    soc_A = 4.0
    soc_B = 4.0
    
    total_time_A = 0.0
    total_time_B = 0.0
    
    # Energy value scaling: 1 MJ of deployed energy on a track with pi=1.0 saves 0.25 seconds
    value_to_time = 0.25
    
    # Magic number: Regen from braking across a full lap (approximated for edge cases)
    regen_per_lap = 2.5 # MJ
    
    # [VISUALIZATION] Setup JSON collection
    data_laps = []
    
    for lap in 1:56
        # --- Gap Analysis ---
        gap = total_time_B - total_time_A
        # If gap > 0, A is ahead. Threat gap is distance B is behind. If B is ahead, A is chasing (no defend reserve needed)
        defend_gap = gap > 0.0 ? gap : 10.0 # 10.0 effectively nullifies threat multiplier
        
        # === CAR A (MPC) LOGIC ===
        predicted_op_soc, reserve_req = estimate_opponent!([soc_B], defend_gap)
        
        # In reality, JuMP solver would be called with suppress warnings.
        # It's already muted with `set_silent(model)` in MPCEngine.
        solver = setup_solver(horizon, track, soc_A, reserve_req)
        u_A, lambda_A = optimize_deployment!(solver, time_limit_ms=100)
        
        energy_A_used = 0.0
        time_saved_A = 0.0
        for k in 1:horizon
            duration = track.nodes[k].length / track.nodes[k].speed_estimate
            e_used = (u_A[k] * duration) / 1000.0
            energy_A_used += e_used
            time_saved_A += e_used * track.nodes[k].marginal_value * value_to_time
        end
        lap_time_A = base_lap_time - time_saved_A
        
        # === CAR B (HEURISTIC) LOGIC ===
        # Heuristic attempts to dump max power on nodes 9 and 1 (long straights)
        u_B = zeros(horizon)
        available_energy = min(9.0, soc_B)
        
        for priority_node in [9, 1, 6, 3] # Priority by straights
            node = track.nodes[priority_node]
            duration = node.length / node.speed_estimate
            max_node_energy = (350.0 * duration) / 1000.0 # 350kW limit
            deploy_energy = min(max_node_energy, available_energy)
            u_B[priority_node] = (deploy_energy * 1000.0) / duration
            available_energy -= deploy_energy
            if available_energy <= 0.01
                break
            end
        end
        
        energy_B_used = 0.0
        time_saved_B = 0.0
        for k in 1:horizon
            duration = track.nodes[k].length / track.nodes[k].speed_estimate
            e_used = (u_B[k] * duration) / 1000.0
            energy_B_used += e_used
            time_saved_B += e_used * track.nodes[k].marginal_value * value_to_time
        end
        
        lap_time_B = base_lap_time - time_saved_B
        
        # [VISUALIZATION] Collect node-by-node state with time passing
        lap_nodes_data = []
        node_cumulative_A = total_time_A
        node_cumulative_B = total_time_B
        
        current_soc_A = soc_A
        current_soc_B = soc_B
        
        for k in 1:horizon
            node = track.nodes[k]
            dur = node.length / node.speed_estimate
            
            # Reconstruct node states
            a_deploy = u_A[k] * dur / 1000.0
            a_time = dur - (a_deploy * node.marginal_value * value_to_time)
            node_cumulative_A += a_time
            current_soc_A -= a_deploy
            
            b_deploy = u_B[k] * dur / 1000.0
            b_time = dur - (b_deploy * node.marginal_value * value_to_time)
            node_cumulative_B += b_time
            current_soc_B -= b_deploy
            
            # Reconstruct HMI
            hmi_str = String(calculate_hmi_signals(node.marginal_value, lambda_A[k], current_soc_A, dur))
            gap_str = round(node_cumulative_A - node_cumulative_B, digits=3)
            
            push!(lap_nodes_data, "{\"node\": $k, \"carA_deploy_kW\": $(u_A[k]), \"carA_time\": $a_time, \"carA_soc\": $(round(current_soc_A, digits=3)), \"carA_hmi\": \"$hmi_str\", \"carB_deploy_kW\": $(u_B[k]), \"carB_time\": $b_time, \"carB_soc\": $(round(current_soc_B, digits=3)), \"gap\": $gap_str}")
        end
        push!(data_laps, "[" * join(lap_nodes_data, ", ") * "]")
        
        # Apply SOC updates at the end of the lap block
        soc_B = min(4.0, soc_B - energy_B_used + regen_per_lap)
        total_time_B += lap_time_B
        
        soc_A = min(4.0, soc_A - energy_A_used + regen_per_lap)
        total_time_A += lap_time_A
        
        # Logging
        # Mute logging for boring laps to not flood output
        if lap <= 3 || lap >= 54 || lap % 10 == 0
            println("--- Lap $lap ---")
            println("Car A (MPC)       | Lap Time: $(round(lap_time_A, digits=3))s | Deployed: $(round(energy_A_used, digits=2)) MJ | SOC End: $(round(soc_A, digits=2)) MJ")
            println("Car B (Heuristic) | Lap Time: $(round(lap_time_B, digits=3))s | Deployed: $(round(energy_B_used, digits=2)) MJ | SOC End: $(round(soc_B, digits=2)) MJ")
            
            # Print Action Deployment Details for visibility
            println("  -> [Car A Actions] Node 9 (Back straight): $(round(u_A[9], digits=0))kW | Node 1 (Pit straight): $(round(u_A[1], digits=0))kW")
            println("  -> [Car B Actions] Node 9 (Back straight): $(round(u_B[9], digits=0))kW | Node 1 (Pit straight): $(round(u_B[1], digits=0))kW")
            println()
        end
    end
    
    println("==================================================")
    println("🏆 RACE RESULTS 🏆")
    println("==================================================")
    
    delta = abs(total_time_A - total_time_B)
    
    if total_time_A < total_time_B
        println("🥇 WINNER: Car A (MPC Agent)")
        println("🥈 2nd Place: Car B (Heuristic Rule-based)")
        println("Margin of Victory: +$(round(delta, digits=3)) seconds")
    elseif total_time_B < total_time_A
        println("🥇 WINNER: Car B (Heuristic Rule-based)")
        println("🥈 2nd Place: Car A (MPC Agent)")
        println("Margin of Victory: +$(round(delta, digits=3)) seconds")
    else
        println("🤝 TIE!")
    end
    
    println("\nTotal Race Time - Car A: $(round(total_time_A, digits=3)) seconds")
    println("Total Race Time - Car B: $(round(total_time_B, digits=3)) seconds")
    println("==================================================")
    
    # [VISUALIZATION] Write to data.js
    println("\nWriting visualization data to visualizer/data.js...")
    track_nodes_json = "[" * join(["{\"id\": $(n.id), \"length\": $(n.length), \"type\": \"$(n.node_type)\", \"margin\": $(n.marginal_value)}" for n in track.nodes], ", ") * "]"
    laps_json = "[" * join(data_laps, ", ") * "]"
    
    open("visualizer/data.js", "w") do f
        write(f, "const RACE_DATA = {\n")
        write(f, "  track: $track_nodes_json,\n")
        write(f, "  laps: $laps_json\n")
        write(f, "};\n")
    end
    println("Done!")
end

run_race()
