// Template for a Standalone Binary Plugin
// This is an independent program that can be called from Neutrino
//
// Replace "my-tool" with your actual tool name

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>

#define PROGRAM_NAME "my-tool"
#define PROGRAM_VERSION "1.0.0"

// Command-line options
static struct option long_options[] = {
	{"help",    no_argument,       0, 'h'},
	{"version", no_argument,       0, 'v'},
	{"output",  required_argument, 0, 'o'},
	{"verbose", no_argument,       0, 'V'},
	{0, 0, 0, 0}
};

// Global configuration
static int verbose = 0;
static char* output_file = NULL;

// Print usage information
static void print_usage(void)
{
	printf("Usage: %s [OPTIONS]\n", PROGRAM_NAME);
	printf("\n");
	printf("Template for a standalone Neutrino plugin tool.\n");
	printf("\n");
	printf("Options:\n");
	printf("  -h, --help         Show this help message\n");
	printf("  -v, --version      Show version information\n");
	printf("  -o, --output FILE  Set output file\n");
	printf("  -V, --verbose      Enable verbose output\n");
	printf("\n");
}

// Print version information
static void print_version(void)
{
	printf("%s version %s\n", PROGRAM_NAME, PROGRAM_VERSION);
	printf("Template for standalone Neutrino plugin\n");
	printf("License: GPL-2.0-or-later\n");
}

// Main tool functionality
static int do_work(void)
{
	if (verbose) {
		printf("[%s] Starting work...\n", PROGRAM_NAME);
	}

	// TODO: Add your tool's main logic here
	// Examples:
	// - Process files
	// - Network operations
	// - System configuration
	// - Data analysis
	// - Media processing

	printf("[%s] Tool executed successfully\n", PROGRAM_NAME);

	if (output_file != NULL) {
		if (verbose) {
			printf("[%s] Writing output to: %s\n", PROGRAM_NAME, output_file);
		}

		FILE* fp = fopen(output_file, "w");
		if (fp == NULL) {
			fprintf(stderr, "[%s] ERROR: Cannot open output file: %s\n",
			        PROGRAM_NAME, output_file);
			return 1;
		}

		fprintf(fp, "Output from %s v%s\n", PROGRAM_NAME, PROGRAM_VERSION);
		fclose(fp);
	}

	if (verbose) {
		printf("[%s] Work completed\n", PROGRAM_NAME);
	}

	return 0;
}

// Main entry point
int main(int argc, char* argv[])
{
	int c;
	int option_index = 0;

	// Parse command-line options
	while ((c = getopt_long(argc, argv, "hvo:V", long_options, &option_index)) != -1) {
		switch (c) {
		case 'h':
			print_usage();
			return 0;

		case 'v':
			print_version();
			return 0;

		case 'o':
			output_file = optarg;
			break;

		case 'V':
			verbose = 1;
			break;

		case '?':
			// getopt_long already printed error message
			return 1;

		default:
			fprintf(stderr, "Unknown option: %c\n", c);
			return 1;
		}
	}

	// Process remaining arguments
	if (optind < argc) {
		if (verbose) {
			printf("[%s] Additional arguments:\n", PROGRAM_NAME);
			while (optind < argc) {
				printf("  - %s\n", argv[optind++]);
			}
		}
	}

	// Execute main functionality
	return do_work();
}
