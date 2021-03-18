import csv
import glob
import os
import math

results = []
for filename in glob.glob('research/crypto_stonk_correlation/data/*.txt'):
    with open(filename) as handle:
        csv_reader = csv.reader(handle)
        label, _ = os.path.splitext(os.path.basename(filename))
        stonk = label.split('-')[0]
        next(csv_reader)
        result = (stonk, [float(v) for v in next(csv_reader)])
        print(result[1])
        if not any([math.isnan(x) for x in result[1]]):
            results.append(result)


for k, data in sorted(results, key=lambda t: t[1][0]):
    print(k, data)