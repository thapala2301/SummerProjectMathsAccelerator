import torch
import torch.nn as nn
import numpy as np
import matplotlib.pyplot as plt

class NeuralSDF(nn.Module):
    def __init__ (self):
        super(NeuralSDF, self).__init__()
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

# Letting z = 0
x = np.linspace(-2,2,256)
y = np.linspace(-2,2,256)

xx,yy = np.meshgrid(x,y) # Gives us two seperate grids one for every x
# co-ordinate and one for every y co-ordinate. (LR, TB)

zz = np.zeros_like(xx)

# Bring everything into one array
points = np.stack([xx.ravel(), yy.ravel(), zz.ravel()], axis=1)

pts = torch.tensor(points, dtype=torch.float32)
with torch.no_grad():
    pred = model(pts).numpy().reshape(256, 256)

plt.figure(figsize=(6,6))
plt.contourf(xx, yy, pred, levels=50, cmap='RdBu')
plt.contour(xx, yy, pred, levels=[0], colors='black', linewidths=2)
plt.title('Neural SDF — sphere cross section at z=0')
plt.savefig('sphere_result.png')
plt.show()