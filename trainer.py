#!/usr/bin/env python3
"""
SENTINEL AI Trainer - Offline neuroevolution and supervised learning
Loads recorded gameplay JSON, trains the neural network, exports weights to Lua-compatible JSON.
"""

import json
import sys
import random
import math
from pathlib import Path
from typing import List, Dict, Tuple, Any

# Neural Network Implementation
class NeuralNetwork:
    def __init__(self, topology: List[int]):
        self.topology = topology
        self.layers = []
        self.generation = 1
        self.fitness = 0.0
        
        # Initialize layers with random weights and biases
        for i in range(len(topology) - 1):
            in_count = topology[i]
            out_count = topology[i + 1]
            layer = {
                "Weights": [[random.uniform(-1, 1) for _ in range(in_count)] for _ in range(out_count)],
                "Biases": [random.uniform(-1, 1) for _ in range(out_count)]
            }
            self.layers.append(layer)
    
    def tanh(self, x: float) -> float:
        return math.tanh(x)
    
    def forward_propagate(self, inputs: List[float]) -> List[float]:
        """Forward pass through the network."""
        current_values = inputs
        for layer in self.layers:
            next_values = []
            for n in range(len(layer["Biases"])):
                sum_val = layer["Biases"][n]
                for k in range(len(current_values)):
                    sum_val += current_values[k] * layer["Weights"][n][k]
                next_values.append(self.tanh(sum_val))
            current_values = next_values
        return current_values
    
    def mutate(self, mutation_rate: float = 0.2, mutation_strength: float = 0.6):
        """Apply random mutations to weights and biases."""
        for layer in self.layers:
            for n in range(len(layer["Biases"])):
                if random.random() < mutation_rate:
                    layer["Biases"][n] += (random.uniform(-1, 1) * mutation_strength)
                for k in range(len(layer["Weights"][n])):
                    if random.random() < mutation_rate:
                        layer["Weights"][n][k] += (random.uniform(-1, 1) * mutation_strength)
    
    def copy(self):
        """Deep copy the network."""
        import copy
        new_net = NeuralNetwork(self.topology)
        new_net.layers = copy.deepcopy(self.layers)
        new_net.generation = self.generation
        new_net.fitness = self.fitness
        return new_net
    
    def to_dict(self) -> Dict:
        """Serialize to Lua-compatible format."""
        return {
            "Gen": self.generation,
            "Layers": self.layers,
            "BestFitness": self.fitness
        }
    
    @staticmethod
    def from_dict(data: Dict, topology: List[int]):
        """Deserialize from Lua-compatible format."""
        net = NeuralNetwork(topology)
        if "Layers" in data:
            net.layers = data["Layers"]
        if "Gen" in data:
            net.generation = data["Gen"]
        if "BestFitness" in data:
            net.fitness = data["BestFitness"]
        return net


def load_gameplay_files(directory: str = ".") -> Tuple[List[List[float]], int]:
    """Load all gameplay_*.json files and interpret them into input vectors."""
    dataset = []
    import_count = 0
    
    for file_path in Path(directory).glob("gameplay_*.json"):
        try:
            with open(file_path, 'r') as f:
                data = json.load(f)
            frames = data.get("frames", [])
            for frame in frames:
                # Interpret frame into input vector (same logic as Lua interpreter)
                inputs = []
                
                # menuOpen
                inputs.append(1.0 if frame.get("menuOpen") else 0.0)
                
                # health ratio
                health = frame.get("health", 0)
                maxHealth = frame.get("maxHealth", 100)
                inputs.append(max(0, min(1, health / maxHealth if maxHealth > 0 else 0)))
                
                # walk speed normalized
                inputs.append(frame.get("walkSpeed", 0) / 30)
                
                # Y position normalized
                pos = frame.get("position", {})
                y = pos.get("y", 0) if isinstance(pos, dict) else 0
                inputs.append(max(-1, min(1, y / 100)))
                
                # ray distances
                rays = frame.get("rays", [])
                for i in range(9):
                    d = rays[i] if i < len(rays) else 60
                    inputs.append((d / 60) if d else 1)
                
                # enemy vector placeholders
                inputs.extend([0, 0, 0, 1, -1])
                
                # danger and danger dir
                inputs.append(frame.get("danger", 0))
                dangerDir = frame.get("dangerDir", {})
                if isinstance(dangerDir, dict):
                    inputs.append(dangerDir.get("x", 0))
                    inputs.append(dangerDir.get("y", 0))
                else:
                    inputs.extend([0, 0])
                
                # sliding door scan
                inputs.append(frame.get("doorScan", -1))
                
                # floor material airborne flag
                inputs.append(1.0 if frame.get("isAir") else -1.0)
                
                # class and weapon numeric values
                inputs.append(frame.get("classVal", 0))
                inputs.append(frame.get("weaponVal", 0))
                
                # memory recurrence (pad zeros)
                inputs.extend([0] * 12)
                
                # inSpawn
                inputs.append(1.0 if frame.get("inSpawn") else -1.0)
                
                # boredom normalized
                boredom = frame.get("boredom", 0)
                inputs.append(min(1, max(0, boredom / 25)))
                
                # pad to 54 inputs
                while len(inputs) < 54:
                    inputs.append(0)
                
                dataset.append(inputs[:54])  # Ensure exactly 54 inputs
            
            import_count += 1
            print(f"  Loaded {file_path.name}: {len(frames)} frames")
        except Exception as e:
            print(f"  Error loading {file_path}: {e}")
    
    return dataset, import_count


def train_neuroevolution(dataset: List[List[float]], generations: int = 100, pop_size: int = 10, 
                        topology: List[int] = None, verbose: bool = True):
    """Train via simplified neuroevolution on recorded gameplay data."""
    if topology is None:
        topology = [54, 60, 45, 30, 12]
    
    if not dataset:
        print("No dataset provided!")
        return None
    
    # Initialize population
    population = [NeuralNetwork(topology) for _ in range(pop_size)]
    best_network = population[0].copy()
    best_fitness_history = []
    
    for gen in range(generations):
        # Evaluate fitness on dataset (simple: forward pass and sum output magnitudes as a proxy)
        for net in population:
            fitness = 0.0
            for inputs in dataset:
                outputs = net.forward_propagate(inputs)
                # Reward networks that produce non-zero, decisive outputs
                fitness += sum(abs(o) for o in outputs) / len(outputs)
            net.fitness = fitness / len(dataset) if dataset else 0
        
        # Sort by fitness
        population.sort(key=lambda x: x.fitness, reverse=True)
        
        # Track best
        if population[0].fitness > best_network.fitness:
            best_network = population[0].copy()
            best_network.generation = gen
        
        best_fitness_history.append(best_network.fitness)
        
        if verbose and (gen % 10 == 0 or gen == generations - 1):
            print(f"  Gen {gen}: Best Fitness = {best_network.fitness:.4f}")
        
        # Breed and mutate for next generation
        survivors = population[:max(2, pop_size // 2)]
        population = survivors.copy()
        while len(population) < pop_size:
            parent = random.choice(survivors).copy()
            parent.mutate()
            population.append(parent)
    
    best_network.generation = generations
    return best_network


def save_brain_json(network: NeuralNetwork, filename: str):
    """Export network to Lua-compatible JSON."""
    with open(filename, 'w') as f:
        json.dump(network.to_dict(), f, indent=2)
    print(f"Brain saved to {filename}")


def load_brain_json(filename: str, topology: List[int] = None) -> NeuralNetwork:
    """Import network from Lua-compatible JSON."""
    if topology is None:
        topology = [54, 60, 45, 30, 12]
    with open(filename, 'r') as f:
        data = json.load(f)
    return NeuralNetwork.from_dict(data, topology)


def main():
    import argparse
    
    parser = argparse.ArgumentParser(
        description="SENTINEL AI Trainer: offline neuroevolution on recorded gameplay."
    )
    parser.add_argument("--mode", default="train", choices=["train", "load", "eval"],
                       help="train: train from scratch; load: load and continue; eval: evaluate on data")
    parser.add_argument("--generations", type=int, default=100, help="Number of generations")
    parser.add_argument("--pop-size", type=int, default=10, help="Population size")
    parser.add_argument("--input-brain", type=str, help="Input brain JSON to load/continue")
    parser.add_argument("--output-brain", type=str, default="sentinel_trained.json", help="Output brain JSON")
    parser.add_argument("--data-dir", type=str, default=".", help="Directory containing gameplay_*.json files")
    parser.add_argument("--topology", type=str, default="54,60,45,30,12", help="Network topology (comma-separated)")
    
    args = parser.parse_args()
    
    topology = [int(x) for x in args.topology.split(",")]
    
    print(f"SENTINEL AI Trainer")
    print(f"  Mode: {args.mode}")
    print(f"  Topology: {topology}")
    print(f"  Data directory: {args.data_dir}")
    
    # Load dataset
    print("\nLoading gameplay data...")
    dataset, count = load_gameplay_files(args.data_dir)
    print(f"  Total: {count} recordings, {len(dataset)} frames")
    
    if args.mode == "train":
        print("\nTraining neuroevolution...")
        best_net = train_neuroevolution(dataset, generations=args.generations, 
                                      pop_size=args.pop_size, topology=topology)
        save_brain_json(best_net, args.output_brain)
    
    elif args.mode == "load":
        if not args.input_brain:
            print("Error: --input-brain required for load mode")
            sys.exit(1)
        print(f"\nLoading brain from {args.input_brain}...")
        net = load_brain_json(args.input_brain, topology)
        print(f"  Generation: {net.generation}, Fitness: {net.fitness:.4f}")
        print("Continuing training...")
        net = train_neuroevolution(dataset, generations=args.generations, 
                                  pop_size=args.pop_size, topology=topology)
        save_brain_json(net, args.output_brain)
    
    elif args.mode == "eval":
        if not args.input_brain:
            print("Error: --input-brain required for eval mode")
            sys.exit(1)
        print(f"\nEvaluating brain on dataset...")
        net = load_brain_json(args.input_brain, topology)
        total_fitness = 0
        for inputs in dataset:
            outputs = net.forward_propagate(inputs)
            total_fitness += sum(abs(o) for o in outputs) / len(outputs)
        avg_fitness = total_fitness / len(dataset) if dataset else 0
        print(f"  Average fitness on dataset: {avg_fitness:.4f}")


if __name__ == "__main__":
    main()
