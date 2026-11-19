/**
 * Declarations of the parts of the Google Maps JavaScript API that the modules use, for PhpStorm only (the API is
 * loaded at runtime from maps.googleapis.com). See https://developers.google.com/maps/documentation/javascript/reference
 */
declare namespace google.maps {
    interface MapsEventListener {
        remove(): void;
    }

    class Map {
        constructor(mapDiv: HTMLElement | null, opts?: object);
    }

    class LatLng {
        constructor(lat: number, lng: number);
    }

    class Marker {
        constructor(opts?: object);

        addListener(eventName: string, handler: Function): MapsEventListener;
    }

    class InfoWindow {
        constructor(opts?: object);

        open(options?: object | Map, anchor?: object): void;
    }

    class Geocoder {
        constructor();

        geocode(request: object, callback?: Function): Promise<object>;
    }
}

declare namespace google.maps.places {
    class Autocomplete {
        constructor(inputField: HTMLInputElement | null, opts?: object);

        addListener(eventName: string, handler: Function): google.maps.MapsEventListener;

        getPlace(): object;
    }
}
