# Objective is to take my PyTorch weights and convert them into .hex files?
# Files where each line is a weight written as a 4-digit hexadecimal number

import numpy as np
import torch.nn as nn

import torch
import os

class NeuralSDF(nn.Module):
    def __init__ (self):
        super (NeuralSDF, self). __init__()
        self.Relu = nn.ReLU()
        self.input_layer = nn.Linear(3,32)
        self.hidden_layer_1 = nn.Linear(32,32)
        self.hidden_layer_2 = nn.Linear(32,32)
        self.output_layer = nn.Linear(32,1)

    def forward (self,x):
        x = self.input_layer(x)
        x = self.Relu(x)
        x = self.hidden_layer_1(x)
        x = self.Relu(x)
        x = self.hidden_layer_2(x)
        x = self.Relu(x)
        output = self.output_layer(x)

        return output
    
model = NeuralSDF()
model.load_state_dict(torch.load('sphere_sdf.pth'))
model.eval()

os.makedirs('weights', exist_ok=True)
# exist_ok = True is there so that if the folder already exists -> No error

def quantise_q4_12(weights):
    output = (weights * 4096) # Multiply by 4096 to shift 12 fractional bits
    output = np.round(output)
    output = output.astype(np.int16) # INT16 conversion
    return output
    
def write_hex_file(weights, filename):
    file = open(filename, 'w')
    
    for w in weights:
        weight_converted = format(int(w) & 0xFFFF, '04x')
        file.write(weight_converted + '\n')

    file.close()


def export_weights(model):
    # Defining layers names and numbers
    layer_names = ['input_layer', 'hidden_layer_1', 'hidden_layer_2', 'output_layer']
    layer_numbers = [1,2,3,4]

    # Get the layer from the model
    for layer_name,layer_num in zip(layer_names, layer_numbers):
        layer = getattr(model, layer_name)

    # Extracts weights and biases -> Converts float32 vals from PyTorch into numpy arrays
        weights = layer.weight.detach().numpy()
        biases = layer.bias.detach().numpy()

    # Loop through each neuron
        for neuron_index in range(weights.shape[0]):
            alpha = weights[neuron_index]
            alpha_quantised = quantise_q4_12(alpha)
            write_hex_file(alpha_quantised, f'weights/w_{layer_num}_{neuron_index}.hex')

            beta = np.array([biases[neuron_index]])            
            beta_quantised = quantise_q4_12(beta)
            write_hex_file(beta_quantised, f'weights/b_{layer_num}_{neuron_index}.hex')
            
export_weights(model)
print('Export Complete')