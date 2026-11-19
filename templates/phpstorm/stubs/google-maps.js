/**
 * Declarations of the parts of the Google Maps JavaScript API that the modules use, for PhpStorm only (the API is
 * loaded at runtime from maps.googleapis.com). See https://developers.google.com/maps/documentation/javascript/reference
 */
var google = {};

google.maps = {};

/**
 * @param {HTMLElement|null} mapDiv
 * @param {Object} [opts]
 * @constructor
 */
google.maps.Map = function (mapDiv, opts) {};

/**
 * @param {number} lat
 * @param {number} lng
 * @constructor
 */
google.maps.LatLng = function (lat, lng) {};

/**
 * @param {Object} [opts]
 * @constructor
 */
google.maps.Marker = function (opts) {};

/**
 * @param {string} eventName
 * @param {Function} handler
 * @return {Object}
 */
google.maps.Marker.prototype.addListener = function (eventName, handler) {};

/**
 * @param {Object} [opts]
 * @constructor
 */
google.maps.InfoWindow = function (opts) {};

/**
 * @param {Object|google.maps.Map} [options]
 * @param {Object} [anchor]
 * @return {void}
 */
google.maps.InfoWindow.prototype.open = function (options, anchor) {};

/**
 * @constructor
 */
google.maps.Geocoder = function () {};

/**
 * @param {Object} request
 * @param {Function} [callback]
 * @return {Promise}
 */
google.maps.Geocoder.prototype.geocode = function (request, callback) {};

google.maps.places = {};

/**
 * @param {HTMLInputElement|null} inputField
 * @param {Object} [opts]
 * @constructor
 */
google.maps.places.Autocomplete = function (inputField, opts) {};

/**
 * @param {string} eventName
 * @param {Function} handler
 * @return {Object}
 */
google.maps.places.Autocomplete.prototype.addListener = function (eventName, handler) {};

/**
 * @return {Object}
 */
google.maps.places.Autocomplete.prototype.getPlace = function () {};
