---
layout: page
title: Generative Flow Networks for Spatial Transcriptomics
description: MS thesis — artificial data generation of spatial transcriptomics with reinforcement learning
importance: 2
related_publications: true
---

**Thesis:** Artificial Data Generation of Spatial Transcriptomics with Reinforcement Learning
**Author:** Magnus Victor Boock — Master Thesis in Computer Science, University of Southern Denmark (June 2025)
**Supervisors:** Richard Röttger, Melih Kandemir

## Introduction

This thesis was carried out in collaboration with the research group Multi-Omics Profiling In Time and Space (MOPITAS), who develop algorithms to increase the spatial resolution of gene-expression data. Cells in tissue behave and function largely based on interactions with their neighbors, so understanding gene expression *and* spatial position at single-cell resolution is valuable for studying disease progression and treatment. The project explores whether such single-cell-resolution spatial datasets can be generated synthetically, to give MOPITAS a known ground truth for evaluating their resolution-enhancing algorithms.

## Problem Statement

Two established technologies each capture only half the picture:
- **Single-cell RNA sequencing (scRNA-seq)** gives high-resolution gene expression per individual cell, but the tissue is dissociated in the process — spatial position is lost.
- **Spatial Transcriptomics (ST)**, e.g. 10x Genomics Visium, preserves spatial position but only at the resolution of *spots* covering ~10 cells each — individual cells within a spot are not distinguished.

Algorithms that try to combine the two (inferring single-cell-resolution spatial data from existing scRNA-seq + ST datasets) have no way to be evaluated against ground truth, because generating either real data type destroys the original tissue. This motivates generating **synthetic** single-cell-resolution spatially-resolved datasets, for which the ground truth is known by construction — with a particular focus on capturing cell-to-cell interactions between neighboring cells, since these directly influence the properties of cell groups.

Existing spatial transcriptomics simulators — e.g. SpatialcoGCN {% cite yin2024spatialcogcn %}, SRTsim {% cite zhu2023srtsim %}, scDesign3 {% cite song2024scdesign3 %}, and scCube {% cite qian2024sccube %} — generate statistically realistic ST-like data, but do not target explicit, ground-truth single-cell-resolution cell-to-cell interaction structure, which this project's RL-based approach is designed to capture.

## Methodology

The project builds on **Generative Flow Networks (GFlowNets)** {% cite bengio2021flownetworks %} {% cite bengio2023foundations %}, a reinforcement learning framework where an agent sequentially constructs an object $x$ with probability *proportional* to its reward, $\pi(x) \propto R(x)$ — rather than the usual RL objective of maximizing expected return along one or a few optimal trajectories. This matters for dataset generation because the goal is *diverse* high-quality tissue layouts, not a single "best" one. GFlowNets were chosen partly by analogy to their prior success in molecule generation, where atoms are sequentially added to a graph — structurally similar to sequentially assigning cell types to positions.

Two GFlowNet training objectives were compared in depth: **Trajectory Balance (TB-GFN)** {% cite malkin2022trajectory %}, which only needs a reward for the *complete* trajectory, and **Forward-Looking (FL-GFN)** {% cite pan2023better %}, which uses intermediate, per-step rewards for more fine-grained credit assignment. TB-GFN was chosen as the primary method because it is difficult to define a correct, deterministic *intermediate* reward for this task, whereas a deterministic terminal reward is straightforward.

Two modeling approaches for representing the tissue-generation problem were developed:
- **Iterative Resolution Zoom (IRZ)** — a divide-and-conquer approach that starts with a coarse grid over the tissue and repeatedly refines it to higher resolution. This was ultimately abandoned: it conceptually clashes with GFlowNet's "sequentially *add* to an object" paradigm (IRZ instead repeatedly revises/undoes prior assignments), and its state representation and lack of spatial structure made learning difficult.
- **Neighborhood Matching (NM)** — the approach used for all final results. It represents the tissue as a fixed hexagonal grid (mirroring 10x Visium's spot layout), where every position has exactly 6 neighbors (padded with an "empty" type at borders). A discrete cell type is assigned to one position at a time and never revisited, matching GFlowNet's sequential, add-only structure. The reward compares, for each cell type, the local neighborhood composition around cells of that type in the generated tissue against the same statistic in a reference tissue, using Jensen-Shannon (or KL) divergence.

For the neural network, a Graph Attention Network (GAT) followed by a feedforward network clearly outperformed a plain feedforward network alone, and was used for all reported results.

## Algorithm

At each step, the Neighborhood Matching agent assigns one remaining cell type to one remaining grid position (action masking ensures the cell-type pool matches the reference exactly). Several reward-shaping schemes were tested — binary, linear, exponential, and an exponential-with-penalty variant that additionally penalizes assignments creating cell-type adjacencies never seen in the reference. The exponential-with-penalty reward gave the sharpest concentration of reward on near-perfect matches and was used for the main results.

A range of auxiliary RL techniques were tested to help training in the large state space: ε-greedy exploration, temperature scaling of the action distribution, entropy regularization, a UCBVI-inspired exploration bonus, learning-rate scheduling (warm-up followed by decay, including cosine annealing with/without warm restarts, and a higher learning rate for the learned $Z_\theta$ parameter), and experience replay on the best terminal states found so far.

## Theoretical Analysis

A key analytical contribution is a combinatorial feasibility bound on the number of distinct terminal states (assignments) $\lvert\mathcal{X}\rvert$ for a reference tissue of $n$ positions with per-type proportions $P_G(t)$:

$$\lvert\mathcal{X}\rvert = \frac{n!}{\prod_{t \in T}(n \cdot P_G(t))!}$$

For a small example (20 spots, 5 cell types with proportions 0.7/0.1/0.1/0.05/0.05), this gives about $7\times10^6$ possible assignments — large but searchable. Scaling only the number of spots up by 3× (to 60) already produces about $3.17\times10^{23}$ possible assignments — far beyond what any search or learning procedure can cover — while a realistic large ST dataset has on the order of 4,000 spots. This combinatorial explosion, rather than model architecture or hyperparameter tuning, is identified as the central obstacle to scaling the approach to real data.

## Results

- **Z-regularizer.** Adding a term that penalizes an unrealistically low learned $Z_\theta$ (the TB-GFN normalizing constant) noticeably sped up convergence across 3 seeds without hurting final reward or the number of distinct high-reward ("perfect") terminal states found (Figure 9) — this regularizer was kept for all later experiments.
- **Medium mock instances.** Training was evaluated on two small synthetic reference tissues, "Scatter" and "Lines" (Figure 7), across combinations of learning-rate schedulers (cosine annealing, with and without warm restarts), temperature decay, and experience replay (Figures 10–11).
  - On *Scatter*, the best TB-GFN configuration (experience replay + cosine annealing) achieved the lowest loss, highest mean reward, and most unique perfect terminal states found. A configuration using learning-rate warm restarts was knocked out of a good local optimum partway through training (~3,500 episodes in), illustrating the instability risk of aggressive LR resets. FL-GFN's best configuration only matched TB-GFN's most basic (no auxiliary-method) configuration — attributed to FL-GFN relying on "pseudorewards" that can't be computed correctly until every neighboring position has been assigned.
  - On *Lines*, TB-GFN configurations performed more similarly to each other, and FL-GFN was less consistent across configurations but reached comparable best-case performance, notably improving when combined with temperature decay.
- **Scaling limit.** Slightly larger instances (e.g. a scatter-like reference enlarged by 2 side-lengths) were not solvable within the same training budget — direct empirical confirmation of the combinatorial bottleneck identified in the theoretical analysis.

Overall, GFlowNets proved capable of learning to reliably sample *many* distinct high-reward tissue layouts sharing the reference's local cell-type sub-structures, on small, simple mock instances — but the maximum achievable reward was not yet sampled exclusively even in the best runs, and performance did not extend to meaningfully larger instances.

## Conclusion

This thesis set out to generate full-scale, single-cell-resolution synthetic Spatial Transcriptomics datasets with a known ground truth, to support MOPITAS's evaluation needs. That end goal was **not reached**: the work is explicitly framed as a feasibility study and proof of concept. The Neighborhood Matching approach, trained with GFlowNets (primarily Trajectory Balance), was shown to reliably learn spatial cell-type structures on small, simplified mock tissues, consistently discovering many high-reward assignments. The dominant limiting factor throughout is the combinatorial size of the state space, not the model architecture, loss function, or hyperparameter tuning — meaning further hyperparameter search alone is unlikely to unlock significantly larger or more complex instances.

The thesis outlines several concrete directions for future work: richer reward functions that look beyond immediate neighbors (e.g. distance-decayed neighborhood weighting); replacing the hand-designed divergence-based reward with a learned critic in a GAN-style setup; dynamically/progressively increasing the required match quality during training (curriculum-style reward shaping); a divide-and-conquer scheme that generates and stitches together independently-modeled sub-tissues; exploration strategies that up-weight rare cell types; and revisiting Forward-Looking GFlowNets with a properly deterministic intermediate reward. Warm-starting training from known good terminal states was attempted but discarded, since it can bias the model toward a non-representative subset of solutions and — more fundamentally — generating such "known good" states is itself as hard as the original problem.
