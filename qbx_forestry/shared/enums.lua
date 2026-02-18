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
