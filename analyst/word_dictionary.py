

class WordDictionary:
    def __init__(self):
        self.current_int = 0
        self.word_to_int = {}
        self.int_to_word = {}

    def learn_and_encode(self, word):
        if word in self.word_to_int:
            return self.word_to_int[word]
        result = self.word_to_int[word] = self.current_int
        self.current_int += 1
        return result