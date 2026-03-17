# Project Overbid: Mathematical Optimization & Heuristic Model Documentation

## 1. Overview
Project Overbid is an edge-computed energy management system designed for the 2026 FIA Formula 1 Regulations. It utilizes **Model Predictive Control (MPC)** to dynamically dispatch a 350kW "Overtake Mode" motor by treating the car's State of Charge (SOC) as a quantifiable grid-scale continuous variable, and track location as a market-clearing price.

This document formalizes the mathematical optimization bounds, system architecture, and opponent heuristics that power the `ClosedLoopSim.jl` simulation loop.

---

## 2. The MPC Mathematical Optimization Model
The core of Project Overbid relies on a Linear Programming (LP) optimization problem solved by the Gurobi engine in `MPCEngine.jl`. 

### Variables
Let the prediction horizon be $N$ nodes (where $N=10$ covers the entirety of the Sepang circuit):
*   $u_k \in \mathbb{R}$: The electrical deployment power (kW) commanded at track node $k$.
*   $soc_k \in \mathbb{R}$: The State of Charge (MJ) available at the start of track node $k$.

### Parameters
*   $soc_{max} = 4.0$ MJ: Total battery storage capacity.
*   $E_{lap\_max} = 9.0$ MJ: 2026 Regulatory limit on maximum deployment per lap.
*   $P_{max} = 350.0$ kW: Peak deployment power output limit.
*   $\Delta t_k = \frac{L_k}{v_k}$: The duration (seconds) spent navigating node $k$, where $L_k$ is the sector length (meters) and $v_k$ is the estimated velocity (m/s).
*   $\pi_k$: The locational **Marginal Value** of a node (representing aerodynamic sensitivity, DRS zones, and slipstream coefficients). Higher $\pi$ indicates greater positional advantage per kW of deployment.
*   $R_{defend}$: A required dynamic SOC reserve threshold determined by the `StateEstimator` module.

### Objective Function
To maximize the absolute lap time delta against the opponent, the solver maximizes the exact numerical advantage extracted from power deployment while penalizing end-of-horizon state depletion:

$$ \max_{u_k} \left[ \sum_{k=1}^{N} \left( \pi_k \cdot u_k \right) + (W_{save} \cdot soc_{N+1}) \right] $$

Where $W_{save} = 150.0$ is the tuned cross-lap arbitrage weight. This constant is strategically tuned to fall geographically between the marginal values of Node 1 and Node 9, tricking the finite-horizon solver into hoarding energy on slow corners specifically for the next lap's straightaway.

### Constraints
1.  **Power Bounds**: $0 \le u_k \le P_{max} \quad \forall k \in [1, N]$
2.  **Storage Bounds**: $0 \le soc_k \le soc_{max} \quad \forall k \in [1, N+1]$
3.  **State Transition (Battery Draw)**: $$ soc_{k+1} = soc_k - \frac{u_k \cdot \Delta t_k}{1000} $$
4.  **Regulatory Cap**: $$ \sum_{k=1}^{N} \frac{u_k \cdot \Delta t_k}{1000} \le E_{lap\_max} $$
5.  **Dynamic Defense Floor**: $soc_{N+1} \ge R_{defend}$

---

## 3. Dynamic State Estimation ($R_{defend}$)
The `StateEstimator.jl` intercepts the kinematic time gap ($\Delta t_{gap}$) between Car A (MPC) and Car B (Heuristic) to calculate the $R_{defend}$ constraint for the JuMP optimizer.

This system provides a smart tactical advantage:
1.  **Attacking Mode ($\Delta t_{gap} < 0.0s$)**: Car A is trailing. 
    *   $R_{defend} = 0.0$ MJ. 
    *   *Result:* The MPC drains the battery entirely if it analytically guarantees an overtake.
2.  **Defending Mode ($0.0s \le \Delta t_{gap} \le 1.0s$)**: Car A is leading, but vulnerable to DRS.
    *   $R_{defend} = 0.5 + 1.0 \cdot (1.0 - \Delta t_{gap})$
    *   *Result:* Car A hoards up to 1.5 MJ of battery linearly correlating to how close Car B is trailing in the DRS zone.
3.  **Cruise Mode ($\Delta t_{gap} > 1.0s$)**: Car A has broken the threat threshold.
    *   $R_{defend} = 0.0$ MJ. 
    *   *Result:* Car A abandons defensive hoarding to extract pure peak lap times.

---

## 4. The Car B Sub-Optimal Heuristic
Car B acts as a baseline, representing a human driver operating on static rule-based instincts rather than mathematical optimization.

### Execution Logic
1.  Car B assesses its current energy budget $E_{budget} = \min(9.0, soc_{current})$.
2.  It traverses a manually hardcoded priority list of the longest track straightaways (For Sepang: `[Node 9, Node 1, Node 6, Node 3]`).
3.  On each priority node, Car B indiscriminately commands maximum deployment limit ($350kW$) restricted only by sector duration tracking.
4.  If the energy budget depletes to $0.0$, all subsequent nodes in the lap receive $0.0kW$ allocation.

### The Delta
Because Car B fails to calculate the geometric marginal value $\pi_k$ or utilize cross-lap arbitrage ($W_{save}$), it frequently dumps all its energy inefficiently on Node 9, leaving itself entirely defenceless against Car A's intelligently reserved stockpile on Node 1.

---

## 5. Shadow Price HMI Integration
The edge computing pipeline features a direct visualization system. When the Gurobi engine solves the MPC, it generates **Dual Variables ($\lambda_{soc}$)** for the dynamic state transition constraints.

These duals represent the exact quantifiable "shadow price", or opportunity cost, of using $1 MJ$ of battery right now relative to saving it for the end of the horizon.

`HMI_Logic.jl` cross-references $\lambda_{soc}$ against the current node's aerodynamic impact string:
*   **Green (Deploy)**: Current node marginal value > Future storage value.
*   **Yellow (Marginal)**: Node value precisely matches storage cost.
*   **Red (Defend)**: Current node value < Future storage value.

These strings are piped back directly into the `visualizer/data.js` telemetry UI, yielding a deterministic steering wheel dashboard for driver intuition.
