
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <error.h>
#include <string.h>

#define GREEN 0.45
#define YELLOW 0.80
#define RED 1

// long sysconf(int name);
// int getloadavg(double loadavg[], int nelm);

int main () {
	long n_cpu;
	double loadavg[3];
	char la[3][32], *prefix;
	int i;

	memset(la[0], 0, sizeof la[0]);
	memset(la[1], 0, sizeof la[1]);
	memset(la[2], 0, sizeof la[2]);
//	memset(prefix, 0, sizeof prefix);

#ifdef _SC_NPROCESSORS_ONLN
	if ( ( n_cpu = sysconf(_SC_NPROCESSORS_ONLN) ) < 0 ) {
		fprintf(stderr, "Could not get number of processors: %m\n");
		return errno;
	}
	if ( n_cpu == 0 ) {
		fprintf(stderr, "We have 0 processors?!\n");
		return 1;
	}

	if ( getloadavg(loadavg, 3) < 0 ) {
		fprintf(stderr, "Could not get load average: %m\n");
		return errno;
	}

	for ( i = 0; i <= 2; ++i ) {
		if ( ( loadavg[i] / n_cpu >= 0 ) && ( loadavg[i] / n_cpu <= GREEN ) ) {
			if ( ( prefix = strndup("32", 2) ) == NULL ) {
				fprintf(stderr, "Could not allocate space for prefix.");
			}
		} else if ( ( loadavg[i] / n_cpu >= GREEN ) && ( loadavg[i] / n_cpu <= YELLOW ) ) {
			if ( ( prefix = strndup("33", 2) ) == NULL ) {
				fprintf(stderr, "Could not allocate space for prefix.");
			}
		} else if ( ( loadavg[i] / n_cpu >= YELLOW ) && ( loadavg[i] / n_cpu <= RED ) ) {
			if ( ( prefix = strndup("31", 2) ) == NULL ) {
				fprintf(stderr, "Could not allocate space for prefix.");
			}
		} else {
			if ( ( prefix = strndup("31;01", 5) ) == NULL ) {
				fprintf(stderr, "Could not allocate space for prefix.");
			}
		}

		sprintf(la[i], "\033[%sm%0.2f\033[00m", prefix, loadavg[i]);
		free(prefix);
	}

	printf("%s,%s,%s\n", la[0], la[1], la[2]);
	return 0;
#else
	fprintf(stderr, "Could not get number of processors on a non-standard system.\n");
	return 1;
#endif
}
