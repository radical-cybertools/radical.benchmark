import os
from glob import glob


if __name__ == '__main__':

    logs = glob('threads_*/gromacs-*')
    prof = open('profile.txt','w')
    prof.write('Threads/Cores Walltime\n')
    for log in logs:
        threads = log.split('/')[0].strip().split('_')[1].strip()
        with open(log,'r') as fp:
            line = fp.readlines()[-7:-6][0].strip().split(' ')
            line = filter(lambda a: a != "", line)
            walltime = line[2]
            print 'Threads/Cores: ',threads,'Walltime: ', walltime
            prof.write('%s %s\n'%(threads,walltime))

    prof.close()
