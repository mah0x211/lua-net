/*
 * Compile the shared socket constant conversions under a module-specific
 * object name.  net.addrinfo also links constants.c, and coverage builds need
 * distinct gcno/gcda paths for the two shared objects.
 */
#include "constants.c"
