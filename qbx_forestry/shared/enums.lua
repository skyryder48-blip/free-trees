-----------------------------------------------------------
-- SHARED: ENUMERATIONS
-- Global constants referenced across client and server.
-----------------------------------------------------------

--- Job name constant used for duty checks.
FORESTRY_JOB = 'lumberjack'

--- Tree size identifiers.
TreeSize = {
    SMALL  = 'small',
    MEDIUM = 'medium',
    LARGE  = 'large',
}

--- Log quality states.
LogQuality = {
    NORMAL  = 'normal',
    DAMAGED = 'damaged',
}

--- Log length identifiers.
LogLength = {
    SHORT    = 'short',
    STANDARD = 'standard',
    LONG     = 'long',
}

--- Crew role identifiers.
CrewRole = {
    LEADER    = 'leader',
    FELLER    = 'feller',
    BUCKER    = 'bucker',
    DRIVER    = 'driver',
    MILLER    = 'miller',
    GENERAL   = 'general',
    SPECIALIST = 'specialist',
}

--- Display labels for enums.
TreeSizeLabels  = { small = 'Small', medium = 'Medium', large = 'Large' }
LogQualityLabels = { normal = 'Normal', damaged = 'Damaged' }
CrewRoleLabels = {
    leader    = 'Leader',
    feller    = 'Feller',
    bucker    = 'Bucker',
    driver    = 'Driver',
    miller    = 'Miller',
    general   = 'General',
    specialist = 'Specialist',
}

--- Standardized error codes returned by server callbacks.
--- Used for consistent client-side error handling.
ErrorCode = {
    NOT_LOADED        = 'not_loaded',
    NO_PLAYER         = 'no_player',
    NO_CACHE          = 'no_cache',
    WRONG_JOB         = 'wrong_job',
    OFF_DUTY          = 'off_duty',
    NO_PERMIT         = 'no_permit',
    COOLDOWN          = 'cooldown',
    ALREADY_FELLED    = 'already_felled',
    UNKNOWN_SPECIES   = 'unknown_species',
    NO_TOOL           = 'no_tool',
    WRONG_TOOL_SIZE   = 'wrong_tool_size',
    TOO_FAR           = 'too_far',
    LEVEL_TOO_LOW     = 'level_too_low',
    MISSING_CERT      = 'missing_cert',
    BROKEN_TOOL       = 'broken',
    NO_FUEL           = 'no_fuel',
    INSUFFICIENT_FUNDS = 'insufficient_funds',
    INVENTORY_FULL    = 'inventory_full',
    ALREADY_IN_CREW   = 'already_in_crew',
    NOT_IN_CREW       = 'not_in_crew',
    CREW_FULL         = 'crew_full',
    NOT_LEADER        = 'not_leader',
    TARGET_OFF_DUTY   = 'target_off_duty',
    SPECIES_MISMATCH  = 'species_mismatch',
    UNKNOWN_RECIPE    = 'unknown_recipe',
    ECONOMY_NOT_LOADED = 'economy_not_loaded',
}

--- Human-readable messages for error codes.
ErrorMessages = {
    [ErrorCode.NOT_LOADED]        = 'Player data not loaded.',
    [ErrorCode.WRONG_JOB]         = 'You need the forestry job.',
    [ErrorCode.OFF_DUTY]          = 'You must be on duty.',
    [ErrorCode.NO_PERMIT]         = 'You need a valid timber permit.',
    [ErrorCode.COOLDOWN]          = 'Please wait before felling again.',
    [ErrorCode.NO_TOOL]           = 'You need a chopping tool.',
    [ErrorCode.WRONG_TOOL_SIZE]   = 'Your tool cannot fell this tree.',
    [ErrorCode.TOO_FAR]           = 'Too far from the tree.',
    [ErrorCode.LEVEL_TOO_LOW]     = 'Your level is too low.',
    [ErrorCode.MISSING_CERT]      = 'Missing required certification.',
    [ErrorCode.BROKEN_TOOL]       = 'Your tool is broken.',
    [ErrorCode.NO_FUEL]           = 'Chainsaw is out of fuel.',
    [ErrorCode.INSUFFICIENT_FUNDS] = 'Not enough money.',
    [ErrorCode.INVENTORY_FULL]    = 'Inventory full.',
    [ErrorCode.ALREADY_IN_CREW]   = 'Already in a crew.',
    [ErrorCode.NOT_IN_CREW]       = 'Not in a crew.',
    [ErrorCode.CREW_FULL]         = 'Crew is full.',
    [ErrorCode.NOT_LEADER]        = 'Only the crew leader can do that.',
    [ErrorCode.TARGET_OFF_DUTY]   = 'That player is not on forestry duty.',
    [ErrorCode.SPECIES_MISMATCH]  = 'Wrong wood species for this recipe.',
}
