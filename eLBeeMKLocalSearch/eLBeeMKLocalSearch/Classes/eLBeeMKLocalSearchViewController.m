//
//  StoresMap.m
//  eLBee
//
//  Created by Jonathon Hibbard on 1/28/13.
//  Copyright (c) 2013 Integrated Events. All rights reserved.
//

#import "eLBeeMKLocalSearchViewController.h"
#import <CoreLocation/CoreLocation.h>
#import <CoreLocation/CLLocationManager.h>
#import <AddressBook/AddressBook.h>
/**
 * Annotation object for all Map Items displayed after Local Search returns matches.
 */
@interface MapItemAnnotationObject : NSObject <MKAnnotation>

@property (nonatomic) CLLocationCoordinate2D coordinate;

// Title and SubTitle are required for MKAnnotation...
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subTitle;

-(id)initUsingCoordinate:(CLLocationCoordinate2D)coordinate mapItemName:(NSString *)mapItemName;
-(id)initUsingCoordinate:(CLLocationCoordinate2D)coordinate mapItemName:(NSString *)mapItemName withOptionalSubTitle:(NSString *)subTitle;
@end



typedef void (^UserLocationFoundCallback)(CLLocationCoordinate2D);

@interface eLBeeMKLocalSearchViewController () <MKMapViewDelegate, CLLocationManagerDelegate, UIAlertViewDelegate>


typedef NS_ENUM(NSInteger, MapViewMode) {
    MapViewModeNormal = 0,
    MapViewModeLoading,
};

@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) UserLocationFoundCallback foundUserLocationCallback;
@property (nonatomic, strong) MapItemAnnotationObject *mapItemPin;
@property (nonatomic, strong) MapItemAnnotationObject *lastMapItemPinTapped;
@property (nonatomic, strong) NSMutableArray *mapItems;
@property (nonatomic, strong) MKLocalSearch *localSearch;
@property (nonatomic, strong) MKLocalSearchRequest *localSearchRequest;

@property (nonatomic) MapViewMode mapViewMode;
@property CLLocationCoordinate2D coords;

@property BOOL userLocationSet;

-(void)searchBarSearchButtonClicked:(UISearchBar *)searchBar;

@end

@implementation eLBeeMKLocalSearchViewController

static CGFloat userPosZoomLat = 0.2;
static CGFloat userPosZoomLon = 0.2;

#pragma mark -
#pragma mark Constructors & Destructors
#pragma mark -

#pragma mark Constructors


-(void)viewDidLoad {

    [super viewDidLoad];

    self.mapView.delegate = self;
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    /**
     * This causes "...CGImageReadSessionGetCachedImageBlockData: readSession [...] has bad readRef..."
     * Did some reading on it... didn't find much except a bunch of theories, points to the bug reporter, etc.
     * Will update whenever we get an answer from apple or a resolution...
     */
    [self.locationManager startUpdatingLocation];
}

#pragma mark Destructors

-(void)didReceiveMemoryWarning {

    [super didReceiveMemoryWarning];

    self.locationManager = nil;
    self.foundUserLocationCallback = nil;
    self.mapItemPin = nil;
    self.lastMapItemPinTapped = nil;
    self.mapItems = nil;
    self.localSearch = nil;
    self.localSearchRequest = nil;
}


#pragma mark -
#pragma mark MKMapKit Methods
#pragma mark -

#pragma mark Load Coordinates by Address
-(void)setupCoordsUsingAddress:(NSString *)address {

    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    [geocoder geocodeAddressString:address completionHandler:^(NSArray *placemarks, NSError *error) {

        if(!error && placemarks && placemarks.count > 0) {
            [self issueLocalSearchLookup:@"retail" usingPlacemarksArray:placemarks];
        }

    }];
}

-(void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    
    CLLocation *userLocation = [locations lastObject];

    self.coords = userLocation.coordinate;
    self.userLocationSet = YES;
    [self centerOverUserLocation];

    if(self.foundUserLocationCallback) {
        self.foundUserLocationCallback(self.coords);
    }

    self.foundUserLocationCallback = nil;

    if(userLocation.horizontalAccuracy <= 100.0f) {
        [self.locationManager stopUpdatingLocation];
    }
}

#pragma mark Center Map At the User's Location

-(void)centerOverUserLocation {
    
    MKCoordinateSpan   local = MKCoordinateSpanMake(userPosZoomLat, userPosZoomLon);
    MKCoordinateRegion region = MKCoordinateRegionMake(self.coords, local);

    CLLocationCoordinate2D location;
    location.latitude = self.coords.latitude;
    location.longitude = self.coords.longitude;
    region.span = local;
    region.center = location;
    
    [self.mapView setRegion:region animated:YES];
}

#pragma mark Handle failing to obtain the current location..
-(void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {

    if(error.code == kCLErrorDenied) {

        [self.locationManager stopUpdatingLocation];

        [[[UIAlertView alloc] initWithTitle:@"Permission Denied"
                                   message:@"Cannot perform local map searches until you enable Map Services!\n\nSettings -> Privacy -> Location Services (set to on) -> eLBeeKMLocalSearch (set to on)"
                                  delegate:nil
                         cancelButtonTitle:@"OK"
                         otherButtonTitles:nil] show];

    } else if(error.code == kCLErrorLocationUnknown) {
        // retry

    } else {
        [[[UIAlertView alloc] initWithTitle:@"Error retrieving location"
                                   message:error.description
                                  delegate:nil
                         cancelButtonTitle:@"OK"
                         otherButtonTitles:nil] show];
    }
}
#pragma mark Load the Map Mode

-(void)setMapViewMode:(MapViewMode)mapViewMode {
    
    _mapViewMode = mapViewMode;

    [self.mapView addAnnotations:self.mapItems];
    if(self.mapItemPin) {
        [self.mapView addAnnotation:self.mapItemPin];
    }
}

#pragma mark Callout for Map Items Pin that was last tapped

-(MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    static NSString *const kPinIdentifier = @"MapItemAnnotation";

    if([annotation isKindOfClass:[MapItemAnnotationObject class]]) {
        MKPinAnnotationView *view = (MKPinAnnotationView*)[mapView dequeueReusableAnnotationViewWithIdentifier:kPinIdentifier];
        if(!view) {
            view = [[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:kPinIdentifier];
            view.canShowCallout = YES;
            view.calloutOffset = CGPointMake(-5, 5);
            view.animatesDrop = YES;
        }
        view.pinColor = MKPinAnnotationColorRed;
        return view;
    }
    return nil;
}

#pragma mark The Callout's Accessory Button(s) Tap Controller
-(void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view calloutAccessoryControlTapped:(UIControl *)control {
    self.lastMapItemPinTapped = (MapItemAnnotationObject *)view.annotation;
}


#pragma mark -
#pragma mark MKLocalSearch Methods
#pragma mark -

#pragma mark Search for Locations by Descriptive Name (String)

// Ex: [self issueLocalSearchLookup:@"grocery"];
-(void)issueSearchLookup:(NSString *)searchString {
    
    // Set the size (local/span) of the region (address, w/e) we want to get search results for.
    
    MKCoordinateSpan   local = MKCoordinateSpanMake(0.6250, 0.6250);
    MKCoordinateRegion region = MKCoordinateRegionMake(self.coords, local);
    
    [self.mapView setRegion:region animated:NO];
    
    self.localSearchRequest = [[MKLocalSearchRequest alloc] init];
    self.localSearchRequest.region = region;
    self.localSearchRequest.naturalLanguageQuery = searchString;
    
    self.localSearch = [[MKLocalSearch alloc] initWithRequest:self.localSearchRequest];
    
    [self.localSearch startWithCompletionHandler:^(MKLocalSearchResponse *response, NSError *error) {

        if(!error){

            [self loadData:response];
            self.mapViewMode = MapViewModeNormal;

            MKCoordinateSpan   local = MKCoordinateSpanMake(0.2, 0.2);
            MKCoordinateRegion region = MKCoordinateRegionMake(self.coords, local);

            [self.mapView setRegion:region animated:NO];
        }
    }];
}


#pragma mark Search Nearby Placemarks for Result with String

// (See issueLocalSearchLookup:searchString: above).
-(void)issueLocalSearchLookup:(NSString *)searchString usingPlacemarksArray:(NSArray *)placemarks {
    
    // Search 0.250km from point for stores.
    CLPlacemark *placemark = placemarks[0];
    CLLocation *location = placemark.location;

    self.coords = location.coordinate;

    [self issueSearchLookup:searchString];
}


#pragma mark Local Search Result(s)

-(void)loadData:(MKLocalSearchResponse *)response {

    NSUInteger matchesCount = [response.mapItems count];
    NSInteger i = 0;

    self.mapItems = [[NSMutableArray alloc] initWithCapacity:matchesCount];
    
    for(MKMapItem *mapItem in response.mapItems){
        
        MKPlacemark *placeMark = mapItem.placemark;

        CLLocationDegrees latitude  = placeMark.coordinate.latitude;
        CLLocationDegrees longitude = placeMark.coordinate.longitude;

        // Add the pair of coordinates
        CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(latitude, longitude);
        
        // Create a new station object with the coordinates created.
        [self.mapItems addObject:[[MapItemAnnotationObject alloc] initUsingCoordinate:coordinate
                                                                          mapItemName:mapItem.name]];
        i++;
    }
}



-(void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {

    [self.mapView removeAnnotations:self.mapView.annotations];

    [self issueSearchLookup:searchBar.text];

	self.searchBar.text = @"";
	[self.searchBar resignFirstResponder];
}

@end


//------------------------------------------------------------------------------------------------

/**
 * MapItemAnnotation Object Implementation ....
 */
@implementation MapItemAnnotationObject

-(id)initUsingCoordinate:(CLLocationCoordinate2D)coordinate mapItemName:(NSString *)mapItemName {
    return [self initUsingCoordinate:coordinate mapItemName:mapItemName withOptionalSubTitle:nil];
}

-(id)initUsingCoordinate:(CLLocationCoordinate2D)coordinate mapItemName:(NSString *)mapItemName withOptionalSubTitle:(NSString *)optionalSubTitle {

    self = [super init];
    if(self) {
        self.title = mapItemName;
        self.coordinate = coordinate;
        if(optionalSubTitle != nil) {
            self.subTitle = optionalSubTitle;
        }
    }
    return self;
}

@end