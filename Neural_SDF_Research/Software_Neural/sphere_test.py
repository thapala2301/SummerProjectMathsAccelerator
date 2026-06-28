# This code is to generate sphere data and train model 80/20 split
# We know a distance formula so we will use that NOT trimesh here
# Assume centre is at the origin

import numpy as np
import torch
import torch.nn as nn
from torch.utils.data import TensorDataset, DataLoader

sample_size = 500000
radius = 1

points = np.random.uniform(-2, 2, (sample_size, 3))
distances = np.sqrt((points**2).sum(axis=1)) - radius

split = int(0.8 * sample_size)

x_train = points[:split]
x_test  = points[split:]
y_train = distances[:split]
y_test  = distances[split:]

np.save('x_train.npy', x_train)
np.save('x_test.npy',  x_test)
np.save('y_train.npy', y_train)
np.save('y_test.npy',  y_test)

# We convert from numpy array to Pytorch Tensor - now we can run on GPU - PARALLELISM!
# Remember - CPU for sequential tasks vs GPU for parallel processing

x_train = np.load('x_train.npy')
x_test = np.load('x_test.npy')
y_train = np.load('y_train.npy')
y_test = np.load('y_test.npy')

X_train = torch.tensor(x_train, dtype=torch.float32)
X_test = torch.tensor(x_test, dtype=torch.float32)
Y_train = torch.tensor(y_train, dtype=torch.float32).unsqueeze(1)
Y_test = torch.tensor(y_test, dtype=torch.float32).unsqueeze(1)

# Y values are 1D so we use unsqueeze to make them 2D to match the network`s 2D traits
# Unsqueeze is NOT the same as transpose
# Transpose is about swapping the components of a 2D grid
# Unsqueeze promots a flat list into a column and LOOKS like tranposing
# Technically y start off as dimensionless and then the 1 adds the column

# In PyTorch every network is defined as a class

class NeuralSDF(nn.Module):
    # Define layers of network
    def __init__(self):
        super(NeuralSDF, self).__init__()
        self.relu = nn.ReLU()
        self.input_layer = nn.Linear(3,32)
        self.hidden_layer_1 = nn.Linear(32,32)
        self.hidden_layer_2 = nn.Linear(32,32)
        self.output_layer = nn.Linear(32,1)

    # Define how data flows through those layers - order of layers
    # Activation is ONLY applied to hidden layers NOT the output layer
    def forward(self,x):
        x = self.input_layer(x)
        x = self.relu(x)
        x = self.hidden_layer_1(x)
        x = self.relu(x)
        x = self.hidden_layer_2(x)
        x = self.relu(x)
        output = self.output_layer(x)

        return output

# Instantiation
model = NeuralSDF()

# Defining loss function - in this case it is the Mean Squared Error
loss = nn.MSELoss()

# Define our Optimiser
optimiser = torch.optim.Adam(model.parameters(), lr=0.001)

# Then we need a DataLoader to handle batching - deals with points in batches
# Network needs to analyse NOT remember the order of data
dataset = TensorDataset(X_train, Y_train)
loader = DataLoader(dataset, batch_size = 4096, shuffle=True)

# Training Loop 
for epoch in range (200):
    model.train()
    for X_batch, Y_batch in loader:
        pred = model(X_batch)
        loss_val = loss(pred, Y_batch)
        optimiser.zero_grad()
        loss_val.backward()
        optimiser.step()

    if epoch % 20 == 0:
        model.eval()
        with torch.no_grad():
            test_pred = model(X_test) 
            test_loss = loss(test_pred, Y_test) 
        model.train() 
        print(f'Epoch {epoch} | Train Loss: {loss_val.item():.6f} | Test Loss: {test_loss.item():.6f}')      

torch.save(model.state_dict(), 'sphere_sdf.pth')
print('Training complete - model saved')