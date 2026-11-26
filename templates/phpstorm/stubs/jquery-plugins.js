/**
 * Declarations for PhpStorm only: jQuery plugins of JavaScript libraries that the modules bundle and that register
 * themselves with a computed name ("$.fn[name] = function ..."), which PhpStorm cannot resolve, so calls like
 * "$(element).offcanvas()" are reported as "Unresolved function or method". tools/configure-phpstorm.py assigns this
 * file to every module as JavaScript library (templates/phpstorm/js-libraries.xml); it is never loaded in a browser.
 */

/**
 * js-offcanvas 1.2.11 (m2-catalog-filter-off-canvas, js-offcanvas.pkgd.min.js): turns the elements into off-canvas
 * panels.
 *
 * @param {{triggerButton: (string|null|undefined), modifiers: (string|undefined), role: (string|undefined),
 *     modal: (boolean|undefined), resize: (boolean|undefined), onOpen: (Function|null|undefined),
 *     onClose: (Function|null|undefined), onInit: (Function|null|undefined)}} [options]
 *
 * @returns {jQuery}
 */
jQuery.fn.offcanvas = function (options) {
    return this;
};

/**
 * js-offcanvas 1.2.11 (m2-catalog-filter-off-canvas, js-offcanvas.pkgd.min.js): turns the elements into buttons that
 * open and close an off-canvas panel.
 *
 * @param {{offcanvas: (string|null|undefined)}} [options]
 *
 * @returns {jQuery}
 */
jQuery.fn.offcanvasTrigger = function (options) {
    return this;
};
