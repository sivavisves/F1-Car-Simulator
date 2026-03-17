module ProjectOverbid

using JuMP
using Gurobi

export TrackMap, Segment, load_sepang_track, load_suzuka_track
export MPCSolver, optimize_deployment!, setup_solver
export estimate_opponent!
export calculate_hmi_signals

include("TrackGrid.jl")
include("MPCEngine.jl")
include("StateEstimator.jl")
include("HMI_Logic.jl")

end # module
