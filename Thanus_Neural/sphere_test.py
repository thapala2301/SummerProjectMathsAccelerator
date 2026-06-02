# This code is to generate sphere data and train model 80/20 split
# We know a distance formula so we will use that NOT trimesh here
# Assume centre is at the origin

import numpy as np

sample_size = 500000
radius = 1

points = np.random.uniform(-2, 2, (sample_size, 3))
distances = np.sqrt((points**2).sum(axis=1)) - radius

