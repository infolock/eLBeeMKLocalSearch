//
//  eLBeeMKLocalSearchViewController.h
//
//  Created by Jonathon Hibbard on 1/29/13.
//

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <MapKit/MapKit.h>

@interface eLBeeMKLocalSearchViewController : UIViewController

@property (nonatomic, weak) IBOutlet MKMapView *mapView;
@property (nonatomic, weak) IBOutlet UISearchBar *searchBar;

@end