#import <Cocoa/Cocoa.h>
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_3
#include <Security/AuthorizationDB.h>
#endif

@interface RPTKeyValuePair : NSObject {
	id _key;
	id _value;
}
- (id)initWithKey:(id)key value:(id)value;
- (id)key;
- (id)value;
- (NSString *)description;
- (void)dealloc;
@end

@interface RPTRightsDataSource : NSObject /*NSComboBoxDataSource*/ {
	NSArray *_rights;
}
- (id)initWithRightsDB:(NSDictionary *)rightsDB;
- (int)numberOfItemsInComboBox:(NSComboBox *)comboBox;
- (id)comboBox:(NSComboBox *)comboBox objectValueForItemAtIndex:(int)index;
- (void)dealloc;
@end

@interface RPTRightsViewDataSource : NSObject /*NSOutlineViewDataSource*/ {
	NSDictionary *_right;
	NSMutableSet *_pairs;
}
- (id)initWithRightDefinition:(NSDictionary *)rightDefinition;
- (id)outlineView:(NSOutlineView *)outlineView child:(int)index ofItem:(id)item;
- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item;
- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item;
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item;

- (void)dealloc;
@end


@interface RightsInspectorDelegate : NSObject {
	IBOutlet NSWindow *inspectorWindow;
    IBOutlet NSComboBox *rightChooser;
    IBOutlet NSOutlineView *rightView;
	
	NSDictionary *_rightsDB;
	NSString *_displayedRight;
	NSString *_systemPreferencesRight;
}
- (id)init;

- (IBAction)refreshView:(NSButton *)sender;
- (IBAction)comboBoxAction:(NSComboBox *)sender;

- (NSDictionary *)rightDefinitionByName:(NSString *)name;
- (void)dealloc;
@end
