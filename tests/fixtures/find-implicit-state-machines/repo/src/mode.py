class Player:
    def __init__(self):
        self.mode = "idle"

    def play(self):
        if self.mode == "idle":
            self.mode = "playing"
