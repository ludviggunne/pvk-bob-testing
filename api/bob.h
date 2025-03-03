#ifndef BOB_H
#define BOB_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stddef.h>

enum bob_channel {
  BOB_MONO_CHANNEL,
  BOB_LEFT_CHANNEL,
  BOB_RIGHT_CHANNEL,
};

/**
 * Information about this visualization
 * returned by `getInfo`.
 */
struct bob_visualization_info {
  /* The name of this visualization */
  const char *name;

  /* A description of this visualization */
  const char *description;

  /* Enabled analysis tools */
  int enabled;
};

/**
 * Types of audio analysis.
 */
enum bob_audio_flags {
  /* Raw audio data */
  BOB_AUDIO_TIME_DOMAIN_MONO = (1 << 0),
  BOB_AUDIO_TIME_DOMAIN_STEREO = (1 << 1),

  /* Frequency domain data */
  BOB_AUDIO_FREQUENCY_DOMAIN_MONO = (1 << 1),
  BOB_AUDIO_FREQUENCY_DOMAIN_STEREO = (1 << 2),

  /* Chromagram */
  BOB_AUDIO_CHROMAGRAM_MONO = (1 << 3),
  BOB_AUDIO_CHROMAGRAM_STEREO = (1 << 4),

  /* Pulse data */
  BOB_AUDIO_PULSE_MONO = (1 << 5),
  BOB_AUDIO_PULSE_STEREO = (1 << 6),

  /* Tempo data */
  BOB_AUDIO_TEMPO_MONO = (1 << 7),
  BOB_AUDIO_TEMPO_STEREO = (1 << 8),
};

struct bob_float_buffer {
  float *ptr;
  size_t size;
};

/**
 * BoB API.
 */
struct bob_api {
  /**
   * BoB context passed to API functions.
   */
  void *context;

  /**
   * Get time domain data for specified channel.
   */
  struct bob_float_buffer (*get_time_data)(void *context, int channel);

  /**
   * Get frequency domain data for specified channel.
   */
  struct bob_float_buffer (*get_frequency_data)(void *context, int channel);

  /**
   * Get chromagram for specified channel.
   * `buf` should point to an array of 12 floats.
   */
  void (*get_chromagram)(void *context, float *buf, int channel);

  /**
   * Get pulse data for specified channel.
   */
  struct bob_float_buffer (*get_pulse_data)(void *context, int channel);

  /**
   * Get tempo for specified channel.
   */
  float (*get_tempo)(void *context, int channel);

  /**
   * Register a float slider.
   */
  int (*register_float_slider)(void *context, const char *name, float min, float max, float default_value);

  /**
   * Register a checkbox.
   */
  int (*register_checkbox)(void *context, const char *name, int default_value);

  /**
   * Check if a UI element is updated since last read.
   */
  int (*ui_element_is_updated)(void *context, int handle);

  /**
   * Get float value from a UI element.
   */
  float (*get_ui_float_value)(void *context, int handle);

  /**
   * Get boolean value from a UI element.
   */
  int (*get_ui_bool_value)(void *context, int handle);
};

/********************************************
 * The following symbols need to be defined *
 * in the visualization instance.           *
 ********************************************/

/**
 * Filled out by BoB runtime before `create` is called.
 */
extern struct bob_api api;

/**
 * Return some info about this visualization.
 */
const struct bob_visualization_info *get_info(void);

/**
 * Initialize visualization.
 * UI parameters should be registered here.
 * Return a pointer to user data, or NULL.
 */
void *create(void);

/**
 * Called for each frame.
 * Audio analysis data is passed in `data`.
 */
void update(void *userdata);

/**
 * Perform potential visualization cleanup.
 */
void destroy(void *userdata);

#ifdef __cplusplus
}
#endif

#endif /* BOB_H */
