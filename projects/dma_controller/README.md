# DMA Controller — RTL to GDSII

## Overview

This project implements a modular Direct Memory Access (DMA) Controller
and takes the design through the ASIC implementation flow from RTL
design toward final GDSII.

The DMA controller is designed to transfer data between a memory
interface and a peripheral interface without requiring continuous
processor intervention.
## Tools used

The project is implemented using Cadence EDA Tools:

- Xcelium — RTL simulation
- Genus — Logic synthesis
- Conformal LEC — Formal equivalence checking
- Tempus — Static timing analysis
- Innovus — Physical design
- Pegasus — Physical verification


## Architecture

The design is divided into the following RTL modules:

- DMA Top
- Control FSM
- Read Engine
- Write Engine
- Address Generator
- Burst Controller
- FIFO Buffer
- Register Bank
- Status Register
- Transfer Counter
- Interrupt Controller

## RTL Verification

The project includes:

- DMA RTL
- System-level testbench
- Memory model
- Peripheral model
- Simulation waveforms

## ASIC Implementation Flow

RTL Design
    ↓
Functional Simulation
    ↓
Logic Synthesis
    ↓
Formal Equivalence Checking (LEC) & Functional Verifycation of Netlist
    ↓
Static Timing Analysis (STA)
    ↓
Floorplanning
    ↓
Placement
    ↓
Clock Tree Synthesis
    ↓
Routing
    ↓
Physical Verification
    ↓
GDSII
