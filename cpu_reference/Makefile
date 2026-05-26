CXX ?= g++
CXXFLAGS ?= -O2 -std=c++17 -Wall -Wextra -pedantic
LDFLAGS ?= -lm

# Keep the source list explicit so the project structure remains easy to read.
SRC = src/main.cpp src/renderer.cpp src/sdf.cpp src/report.cpp
OBJ = $(SRC:.cpp=.o)

TARGET = cpu_raymarch

all: $(TARGET)

$(TARGET): $(OBJ)
	$(CXX) $(CXXFLAGS) -o $@ $(OBJ) $(LDFLAGS)

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f $(TARGET) $(OBJ)

.PHONY: all clean
