//
//  SecondViewController.m
//  Commute Buddy
//
//  Created by Samuel Ash on 2017-03-22.
//  Copyright © 2017 Samuel Ash. All rights reserved.
//

#import "SecondViewController.h"
#import "CrumbPath.h"
#import "CrumbPathRenderer.h"
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

@interface SecondViewController () <MKMapViewDelegate, CLLocationManagerDelegate>{
    CLLocationManager *locationManager;
    CLLocation *currentLocation;
}

@end

@implementation SecondViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.mapView.showsUserLocation = YES;
    
    
    self.view.backgroundColor=[UIColor whiteColor];
    
    locationManager = [CLLocationManager new];
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0 && [CLLocationManager authorizationStatus] != kCLAuthorizationStatusAuthorizedWhenInUse)
    {
        [locationManager requestAlwaysAuthorization];
    }
    
    locationManager.delegate = self;
    [_mapView setDelegate:self];
    locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    locationManager.distanceFilter = kCLDistanceFilterNone;
    [locationManager startUpdatingLocation];
    
    currentLocation = [locationManager location];
    
    CLLocationCoordinate2D coordinate;
    coordinate.longitude = currentLocation.coordinate.longitude;
    coordinate.latitude = currentLocation.coordinate.latitude;
    
    
    if((currentLocation.coordinate.longitude== 0.0 ) && (currentLocation.coordinate.latitude==0.0))
    {
        UIAlertView *alert = [[UIAlertView alloc ] initWithTitle:(@"Error:")message:(@"Could not get your location.") delegate:nil cancelButtonTitle:nil otherButtonTitles:(@"OK"), nil];
        [alert show];
        
    }
    
    else
    {
        
        coordinate = [currentLocation coordinate];
        
        NSLog(@"Latitude of User is %f",coordinate.longitude);
        NSLog(@"Longitude of User is %f",coordinate.latitude);
    }
    
    [locationManager startUpdatingLocation];
    
    self.myGeocoder = [[CLGeocoder alloc] init];
    [self.myGeocoder reverseGeocodeLocation:currentLocation completionHandler:^(NSArray *placemarks, NSError *error) {
        NSLog(@"Finding city");
        if (error) {
            NSLog(@"Error %@", error.description);
        } else {
            NSLog(@"Latitude = %.6f", currentLocation.coordinate.latitude);
            NSLog(@"Longitude = %.6f", currentLocation.coordinate.longitude);
            MKPlacemark *placemark = [placemarks objectAtIndex:0];
            NSLog(@"city name: %@", placemark.locality);
        }
    }];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    
    CLLocation *location = [locations lastObject];
    
    if (self.crumbs == nil)
    {
        // This is the first time we're getting a location update, so create
        // the CrumbPath and add it to the map.
        //
        _crumbs = [[CrumbPath alloc] initWithCenterCoordinate:location.coordinate];
        [self.mapView addOverlay:self.crumbs level:MKOverlayLevelAboveRoads];
        
        // on the first location update only, zoom map to user location
        CLLocationCoordinate2D newCoordinate = location.coordinate;
        
        // default -boundingMapRect size is 1km^2 centered on coord
        MKCoordinateRegion region = [self coordinateRegionWithCenter:newCoordinate approximateRadiusInMeters:2500];
        
        [self.mapView setRegion:region animated:YES];
    }
    else
    {
        // This is a subsequent location update.
        //
        // If the crumbs MKOverlay model object determines that the current location has moved
        // far enough from the previous location, use the returned updateRect to redraw just
        // the changed area.
        //
        BOOL boundingMapRectChanged = NO;
        MKMapRect updateRect = [self.crumbs addCoordinate:location.coordinate boundingMapRectChanged:&boundingMapRectChanged];
        if (boundingMapRectChanged)
        {
            // MKMapView expects an overlay's boundingMapRect to never change (it's a readonly @property).
            // So for the MapView to recognize the overlay's size has changed, we remove it, then add it again.
            [self.mapView removeOverlays:self.mapView.overlays];
            _crumbPathRenderer = nil;
            [self.mapView addOverlay:self.crumbs level:MKOverlayLevelAboveRoads];
            
            MKMapRect r = self.crumbs.boundingMapRect;
            MKMapPoint pts[] = {
                MKMapPointMake(MKMapRectGetMinX(r), MKMapRectGetMinY(r)),
                MKMapPointMake(MKMapRectGetMinX(r), MKMapRectGetMaxY(r)),
                MKMapPointMake(MKMapRectGetMaxX(r), MKMapRectGetMaxY(r)),
                MKMapPointMake(MKMapRectGetMaxX(r), MKMapRectGetMinY(r)),
            };
            NSUInteger count = sizeof(pts) / sizeof(pts[0]);
            MKPolygon *boundingMapRectOverlay = [MKPolygon polygonWithPoints:pts count:count];
            [self.mapView addOverlay:boundingMapRectOverlay level:MKOverlayLevelAboveRoads];
        }
        else if (!MKMapRectIsNull(updateRect))
        {
            // There is a non null update rect.
            // Compute the currently visible map zoom scale
            MKZoomScale currentZoomScale = (CGFloat)(self.mapView.bounds.size.width / self.mapView.visibleMapRect.size.width);
            // Find out the line width at this zoom scale and outset the updateRect by that amount
            CGFloat lineWidth = MKRoadWidthAtZoomScale(currentZoomScale);
            updateRect = MKMapRectInset(updateRect, -lineWidth, -lineWidth);
            // Ask the overlay view to update just the changed area.
            [self.crumbPathRenderer setNeedsDisplayInMapRect:updateRect];
        }
    }

}

- (MKCoordinateRegion)coordinateRegionWithCenter:(CLLocationCoordinate2D)centerCoordinate approximateRadiusInMeters:(CLLocationDistance)radiusInMeters
{
    // Multiplying by MKMapPointsPerMeterAtLatitude at the center is only approximate, since latitude isn't fixed
    //
    double radiusInMapPoints = radiusInMeters*MKMapPointsPerMeterAtLatitude(centerCoordinate.latitude);
    MKMapSize radiusSquared = {radiusInMapPoints,radiusInMapPoints};
    
    MKMapPoint regionOrigin = MKMapPointForCoordinate(centerCoordinate);
    MKMapRect regionRect = (MKMapRect){regionOrigin, radiusSquared}; //origin is the top-left corner
    
    regionRect = MKMapRectOffset(regionRect, -radiusInMapPoints/2, -radiusInMapPoints/2);
    
    // clamp the rect to be within the world
    regionRect = MKMapRectIntersection(regionRect, MKMapRectWorld);
    
    MKCoordinateRegion region = MKCoordinateRegionForMapRect(regionRect);
    return region;
}

#pragma mark - MapKit

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id <MKOverlay>)overlay
{
    MKOverlayRenderer *renderer = nil;
    
    if ([overlay isKindOfClass:[CrumbPath class]])
    {
        if (self.crumbPathRenderer == nil)
        {
            _crumbPathRenderer = [[CrumbPathRenderer alloc] initWithOverlay:overlay];
        }
        renderer = self.crumbPathRenderer;
    }
    else if ([overlay isKindOfClass:[MKPolygon class]])
    {
#if kDebugShowArea
        if (![self.drawingAreaRenderer.polygon isEqual:overlay])
        {
            _drawingAreaRenderer = [[MKPolygonRenderer alloc] initWithPolygon:overlay];
            self.drawingAreaRenderer.fillColor = [[UIColor blueColor] colorWithAlphaComponent:0.25];
        }
        renderer = self.drawingAreaRenderer;
#endif
    }
    
    return renderer;
}

-(void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status
{
    switch (status)
    {
        case kCLAuthorizationStatusNotDetermined:
        case kCLAuthorizationStatusRestricted:
        case kCLAuthorizationStatusDenied:
        {
            [locationManager requestAlwaysAuthorization];
        }
            break;
        default:
        {
            [locationManager startUpdatingLocation];
        }
            break;
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    NSLog(@"Error while getting core location : %@",[error localizedFailureReason]);
    if ([error code] == kCLErrorDenied)
    {
        //location service was declined by user
    }
    [manager stopUpdatingLocation];
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)setMapType:(UISegmentedControl *)sender {
    switch (sender.selectedSegmentIndex) {
        case 0:
            self.mapView.mapType = MKMapTypeStandard;
            break;
        case 1:
            self.mapView.mapType = MKMapTypeSatellite;
            break;
        case 2:
            self.mapView.mapType = MKMapTypeHybrid;
            break;
        default:
            break;
    }
}

- (IBAction)zoomToCurrentLocation:(UIBarButtonItem *)sender {
    float spanX = 0.00725;
    float spanY = 0.00725;
    MKCoordinateRegion region;
    
    currentLocation = [locationManager location];
    
    CLLocationCoordinate2D coordinate;
    coordinate.longitude = currentLocation.coordinate.longitude;
    coordinate.latitude = currentLocation.coordinate.latitude;
    
    
    if((currentLocation.coordinate.longitude== 0.0 ) && (currentLocation.coordinate.latitude==0.0))
    {
        UIAlertView *alert2 = [[UIAlertView alloc ] initWithTitle:(@"Server Error:")message:(@"Internet Problem. Try Later !!!") delegate:nil cancelButtonTitle:nil otherButtonTitles:(@"OK"), nil];
        [alert2 show];
        
    }
    
    else
    {
        
        
        coordinate = [currentLocation coordinate];
    
        region.center.latitude = coordinate.latitude;
        region.center.longitude = coordinate.longitude;
        region.span.latitudeDelta = spanX;
        region.span.longitudeDelta = spanY;
        
        NSLog(@"Latitude of User is %f",coordinate.longitude);
        NSLog(@"Longitude of User is %f",coordinate.latitude);
    }
    
    [locationManager startUpdatingLocation];
    [self.mapView setRegion:region animated:YES];
}

-(BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    return YES;
}
- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{
    float latitude=newLocation.coordinate.latitude;
    float longitude=newLocation.coordinate.longitude;
    NSLog(@"%f",latitude);
    NSLog(@"%f",longitude);
    [locationManager stopUpdatingLocation];
    
}

@end
