# TrackGrid.jl
# Models the track map as discretized spatial nodes

struct Segment
    id::Int
    length::Float64        # meters
    speed_estimate::Float64 # average speed in m/s
    node_type::Symbol       # :straight, :corner, :braking
    marginal_value::Float64 # \pi - locational marginal value of energy
end

struct TrackMap
    name::String
    length_total::Float64
    nodes::Vector{Segment}
end

function load_sepang_track()
    # Simplified Sepang F1 Circuit Profile (as requested)
    # The track nodes are discretized for the MPC solver.
    
    nodes = Segment[]
    
    # Node 1: Pit Straight - High value for deployment
    push!(nodes, Segment(1, 900.0, 80.0, :straight, 1.5))
    # Node 2: T1/T2 Complex - Low value (traction limited)
    push!(nodes, Segment(2, 300.0, 35.0, :corner, 0.2))
    # Node 3: T3 to T4 - Medium straight
    push!(nodes, Segment(3, 500.0, 75.0, :straight, 0.8))
    # Node 4: T5/T6 - High speed sweeping
    push!(nodes, Segment(4, 600.0, 70.0, :corner, 0.7))
    # Node 5: T7/T8
    push!(nodes, Segment(5, 400.0, 50.0, :corner, 0.5))
    # Node 6: T9 to T11 straight
    push!(nodes, Segment(6, 600.0, 80.0, :straight, 0.9))
    # Node 7: T12 to T13
    push!(nodes, Segment(7, 400.0, 65.0, :corner, 0.6))
    # Node 8: T14 braking and corner
    push!(nodes, Segment(8, 200.0, 40.0, :corner, 0.3))
    # Node 9: Back Straight - Highest value + DRS
    push!(nodes, Segment(9, 924.0, 85.0, :straight, 2.0))
    # Node 10: T15 (Final Hairpin)
    push!(nodes, Segment(10, 219.0, 30.0, :braking, 0.4))
    
    total_length = sum(n.length for n in nodes)
    return TrackMap("Sepang International Circuit", total_length, nodes)
end

function load_suzuka_track()
    # Complex Figure-8 Suzuka Circuit Profile (18 Nodes)
    # This highly technical track requires strategic energy saving.
    
    nodes = Segment[]
    
    # Node 1: Pit Straight (Medium Value)
    push!(nodes, Segment(1, 800.0, 80.0, :straight, 1.2))
    # Node 2-3: First Curve and S-Curves (Traction limited, technical)
    push!(nodes, Segment(2, 400.0, 45.0, :corner, 0.4))
    push!(nodes, Segment(3, 850.0, 50.0, :corner, 0.5))
    # Node 4: Dunlop Curve (High speed sweeper)
    push!(nodes, Segment(4, 300.0, 65.0, :corner, 0.8))
    # Node 5: Degner 1 & 2 (Hard braking)
    push!(nodes, Segment(5, 250.0, 35.0, :braking, 0.2))
    # Node 6: Short link under bridge
    push!(nodes, Segment(6, 300.0, 70.0, :straight, 0.9))
    # Node 7: Hairpin (Extremely slow)
    push!(nodes, Segment(7, 200.0, 20.0, :braking, 0.1))
    # Node 8: Long curve to Spoon (Medium-High Value)
    push!(nodes, Segment(8, 700.0, 75.0, :straight, 1.4))
    # Node 9: Spoon Curve (Technical double apex)
    push!(nodes, Segment(9, 450.0, 40.0, :corner, 0.4))
    # Node 10: Back Straight towards 130R (Highest Value + DRS)
    push!(nodes, Segment(10, 1000.0, 88.0, :straight, 2.5))
    # Node 11: 130R (Flat out)
    push!(nodes, Segment(11, 200.0, 85.0, :corner, 1.0))
    # Node 12: Casio Triangle (Chicane, extreme braking)
    push!(nodes, Segment(12, 157.0, 25.0, :braking, 0.3))
    
    total_length = sum(n.length for n in nodes)
    return TrackMap("Suzuka International Racing Course", total_length, nodes)
end
