FOREACH(file ${SOURCE_FILES})
    IF (file MATCHES ".*Vec8.*")
        IF (MSVC)
            SET_SOURCE_FILES_PROPERTIES(${file} PROPERTIES COMPILE_FLAGS "${EXTRA_COMPILE_FLAGS} /arch:AVX /D__AVX__")
        ELSE (MSVC)
            IF (NOT ANDROID)
                SET_SOURCE_FILES_PROPERTIES(${file} PROPERTIES COMPILE_FLAGS "${EXTRA_COMPILE_FLAGS} -msse4.1 -mavx")
            ENDIF (NOT ANDROID)
        ENDIF (MSVC)
    ELSE (file MATCHES ".*Vec8.*")
        IF (NOT MSVC)
            IF (NOT ANDROID)
                SET_SOURCE_FILES_PROPERTIES(${file} PROPERTIES COMPILE_FLAGS "${EXTRA_COMPILE_FLAGS} -msse4.1")
            ENDIF (NOT ANDROID)
        ENDIF (NOT MSVC)
    ENDIF (file MATCHES ".*Vec8.*")
ENDFOREACH(file)
ADD_LIBRARY(${SHARED_TARGET} SHARED ${SOURCE_FILES} ${SOURCE_INCLUDE_FILES} ${API_ABS_INCLUDE_FILES})

TARGET_LINK_LIBRARIES(${SHARED_TARGET} ${OPENMM_LIBRARY_NAME} ${PTHREADS_LIB})
SET_TARGET_PROPERTIES(${SHARED_TARGET} PROPERTIES LINK_FLAGS "${EXTRA_COMPILE_FLAGS}" COMPILE_FLAGS "${EXTRA_COMPILE_FLAGS} -DOPENMM_CPU_BUILDING_SHARED_LIBRARY")

INSTALL_TARGETS(/lib/plugins RUNTIME_DIRECTORY /lib/plugins ${SHARED_TARGET})
