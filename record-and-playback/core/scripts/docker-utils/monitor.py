from datetime import datetime
import numpy as np
# https://stackoverflow.com/a/55993960
import matplotlib; matplotlib.use('PDF'); import matplotlib.pyplot as plt

import cpuinfo
import psutil
import signal
import time

# https://stackoverflow.com/a/31464349
class GracefulKiller:
  kill_now = False
  def __init__(self):
    signal.signal(signal.SIGINT, self.exit_gracefully)
    signal.signal(signal.SIGTERM, self.exit_gracefully)

  def exit_gracefully(self,signum, frame):
    self.kill_now = True

starttime = time.time()
sleep = 10

process_dict = dict()
count = 0

stats = dict()
timeline = []

def check_parent(pid, fallback_name):
  try:
    p = psutil.Process(pid)
    name = p.name()
    if name == 'GeckoMain':
      return 'firefox'
    elif name in [ 'convert', 'ffmpeg', 'Xvfb', 'gst-launch-1.0', 'pdftocairo', 'pulseaudio', 'nginx' ]:
      return name
    else:
      return check_parent(p.ppid(), name)
  except psutil.NoSuchProcess as err:
    return fallback_name

killer = GracefulKiller()
while not killer.kill_now:
  for pid in psutil.pids():
    if not pid in process_dict:
      try:
        p = psutil.Process(pid)
        name = check_parent(pid, p.name())
        process_dict[pid] = { 'name': name, 'process': p }
      except psutil.NoSuchProcess as err:
        continue

  timeline.append(count)

  for pid, p in process_dict.items():
    instant_cpu = 0.0
    instant_memory = 0
    if p['process'].is_running():
      try:
        instant_cpu = p['process'].cpu_percent() / 100
        instant_memory = p['process'].memory_info().rss / pow(2, 20)
      except psutil.NoSuchProcess as err:
        pass

    if not p['name'] in stats:
      if count == 0:
        stats[p['name']] = { 'cpu': [], 'memory': [] }
      else:
        stats[p['name']] = { 'cpu': [0.0] * count, 'memory': [0] * count }

    if len(stats[p['name']]['cpu']) == count + 1:
      stats[p['name']]['cpu'][-1] += instant_cpu
      stats[p['name']]['memory'][-1] += instant_memory
    else:
      stats[p['name']]['cpu'].append(instant_cpu)
      stats[p['name']]['memory'].append(instant_memory)

  count += 1
  time.sleep(sleep - ((time.time() - starttime) % sleep))

x = timeline
y_cpu = [ i['cpu'] for i in stats.values() ]
y_memory = [ i['memory'] for i in stats.values() ]

plt.ioff()

for key, y in { 'cpu': y_cpu, 'memory': y_memory }.items():
  fig, ax = plt.subplots(figsize=(12, 6))
  ax.stackplot(x, y, labels=stats.keys())

  # shrink current axis by 10%
  box = ax.get_position()
  ax.set_position([box.x0, box.y0, box.width * 0.9, box.height])

  # hide marks and labels on the x axis
  ax.set_xticks([])

  ax.legend(bbox_to_anchor=(1, 1), loc='upper left')
  ax.set_title(cpuinfo.get_cpu_info()['brand'])

  plt.savefig('/stats/' + key + '.png')
