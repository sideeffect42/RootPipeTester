#import "RightsInspectorDelegate.h"

#define ORDER_RIGHTS_BY_NAME 1
#define POLICY_DATABASE_FILE @"/private/etc/authorization"

@implementation RPTKeyValuePair

- (id)initWithKey:(id)key value:(id)value {
	if ((self = [super init])) {
		_key = [key retain];
		_value = [value retain];
	}
	return self;
}
- (id)key {
	return _key;
}
- (id)value {
	return _value;
}
- (NSString *)description {
	return [NSString stringWithFormat:@"{ %@ : %@ }", [self key], [self value]];
}
- (void)dealloc {
	[_key release];
	[_value release];
	[super dealloc];
}

@end

@implementation RPTRightsDataSource

- (id)initWithRightsDB:(NSDictionary *)rightsDB {
	if ((self = [super init])) {
		NSArray *rightKeys = [rightsDB allKeys];
		#if ORDER_RIGHTS_BY_NAME
			rightKeys = [rightKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
		#endif
		
		_rights = [rightKeys retain];
	}
	return self;
}
- (id)init {
	return [self initWithRightsDB:nil];
}

- (int)numberOfItemsInComboBox:(NSComboBox *)comboBox {
	return [_rights count];
}

- (id)comboBox:(NSComboBox *)comboBox objectValueForItemAtIndex:(int)index {
	return [_rights objectAtIndex:index];
}

- (unsigned)comboBox:(NSComboBox *)comboBox indexOfItemWithStringValue:(NSString *)string {
	return [_rights indexOfObject:string];
}

- (void)dealloc {
	[_rights release];
	[super dealloc];
}

@end

@implementation RPTRightsViewDataSource

- (id)initWithRightDefinition:(NSDictionary *)rightDefinition {
	if ((self = [super init])) {
		_pairs = [[NSMutableSet alloc] initWithCapacity:[rightDefinition count] /* just a guess, most keys are scalar */];
		_right = [[NSDictionary alloc] initWithDictionary:rightDefinition];
	}
	return self;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(int)index ofItem:(id)item {
	NSArray *orderedChildList = nil;
	id key = nil, value = nil;
	
	item = (item ? [item value] : _right);
	
	if ([item isKindOfClass:[NSDictionary class]]) {
		orderedChildList = [[item allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
		key = [orderedChildList objectAtIndex:index];
		value = [item objectForKey:key];
	} else if ([item isKindOfClass:[NSArray class]]) {
		orderedChildList = [item sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
		key = @"";
		value = [orderedChildList objectAtIndex:index];
	} else {
		key = item;
		value = @"";
	}
	
	RPTKeyValuePair *pair = [[RPTKeyValuePair alloc] initWithKey:key value:value];
	[_pairs addObject:pair]; // store pair in _pairs for memory management
	[pair release];
	
	return pair;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
	return ([self outlineView:outlineView numberOfChildrenOfItem:item] > 0);
}

- (int)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
	item = (item ? [item value] : _right);
	return ([item respondsToSelector:@selector(count)] ? [item count] : 0);
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
	NSString *colId = [tableColumn identifier];
	id object = nil;
	
	if ([colId isEqualToString:@"key"]) {
		object = [item key];
	} else if ([colId isEqualToString:@"value"]) {
		object = [item value];
	}
	
	if (!object) {
		return @""; // object is nil
	} else if ([object isKindOfClass:[NSString class]]) {
		return object;
	} else if (CFGetTypeID(object) == CFBooleanGetTypeID()) {
		return ([object boolValue] ? @"true" : @"false");
	} else if ([object isKindOfClass:[NSArray class]]) {
		return @"(Array)";
	} else if ([object isKindOfClass:[NSDictionary class]]) {
		return @"(Dictionary)";
	} else {
		return [NSString stringWithFormat:@"%@", object]; // maybe the object can be formatted to a string
	}
}
- (void)dealloc {
	[_pairs release];
	[_right release];
	[super dealloc];
}

@end


@interface RightsInspectorDelegate (PrivateMethods)
- (BOOL)loadPolicyDBFromPath:(NSString *)path;
- (void)windowDidBecomeKey:(NSNotification *)notification;
- (void)updateOutlineViewWithRightName:(NSString *)rightName;
- (void)updateOutlineViewWithSelectionOfComboBox:(NSComboBox *)comboBox;
@end

@implementation RightsInspectorDelegate

Class NSAdminPreference = NULL;

- (id)init {
	if ((self = [super init])) {
		NSAdminPreference = NSClassFromString(@"NSAdminPreference");
		_rightsDB = nil;
		_displayedRight = nil;
		_systemPreferencesRight = @"system.preferences"; // default
		
		if (NSAdminPreference) {
			// ask it for the appropriate System Preferences right
			id adminPreference = [[NSAdminPreference alloc] init];
			if ([adminPreference respondsToSelector:@selector(authorizationString)]) {
				char *prefStr = (char *)[adminPreference performSelector:@selector(authorizationString)];
				_systemPreferencesRight = [[NSString alloc] initWithUTF8String:prefStr];
			}
			[adminPreference release];
		}
		
	}
	return self;
}

- (BOOL)loadPolicyDBFromPath:(NSString *)path {
	[_rightsDB release];
	_rightsDB = [(([(_rightsDB = [NSDictionary dictionaryWithContentsOfFile:path]) objectForKey:@"rights"]) ?: _rightsDB) retain]; // 10.2.x doesn't have a rights subkey
	
	return ([_rightsDB isKindOfClass:[NSDictionary class]] && [_rightsDB count] > 0);
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
	static BOOL inspectorWindowHasInitialized = NO;
	if (inspectorWindowHasInitialized || [notification object] != inspectorWindow) return;
	inspectorWindowHasInitialized = YES;
	
	// Load Policy Database
	if (![self loadPolicyDBFromPath:POLICY_DATABASE_FILE]) { 
		NSRunAlertPanel(@"Error", [NSString stringWithFormat:@"An error occurred while loading the Policy Database from \"%@\".", POLICY_DATABASE_FILE], nil, nil, nil);
		return;
	}
	
	// Initialise Combo Box Values
	[rightChooser setDataSource:[[RPTRightsDataSource alloc] initWithRightsDB:_rightsDB]];
	[rightChooser reloadData];
	
	// Select "System Preferences right" by default	
	[rightChooser selectItemAtIndex:[[rightChooser dataSource] comboBox:rightChooser indexOfItemWithStringValue:_systemPreferencesRight]];
	[self updateOutlineViewWithSelectionOfComboBox:rightChooser];
}

- (NSDictionary *)rightDefinitionByName:(NSString *)name {
	NSDictionary *rightDefinition = nil;
	OSStatus (*rightget)(const char *, CFDictionaryRef *) = NULL;

	CFBundleRef securityBundle = CFBundleGetBundleWithIdentifier((CFStringRef)@"com.apple.security");

	if (securityBundle != NULL &&
	   (rightget = CFBundleGetFunctionPointerForName(securityBundle, (CFStringRef)@"AuthorizationRightGet"))) {
		// Ask Authorization Services for the dictionary (10.3+)
		OSStatus status = (*rightget)([name UTF8String], (CFDictionaryRef *)&rightDefinition); // rightDefinition is autoreleased
		if (status != errAuthorizationSuccess) return nil;
	} else {
		// Read from the Policy Database ourselfs *sigh* (10.2.x)
		[self loadPolicyDBFromPath:POLICY_DATABASE_FILE]; // reload DB
		// TODO: Parse and associate XML comments :/
		rightDefinition = [_rightsDB objectForKey:name];
	}
	
	return rightDefinition;
}

- (void)updateOutlineViewWithRightName:(NSString *)rightName {
	NSDictionary *rightDefinition = [self rightDefinitionByName:rightName];	
	[rightView setDataSource:[[RPTRightsViewDataSource alloc] initWithRightDefinition:rightDefinition]];
	
	// Update _displayedRight
	[_displayedRight release];
	_displayedRight = [rightName retain];
}

- (void)updateOutlineViewWithSelectionOfComboBox:(NSComboBox *)comboBox {
	NSString *rightName = [[comboBox dataSource] comboBox:comboBox objectValueForItemAtIndex:[comboBox indexOfSelectedItem]];
	[self updateOutlineViewWithRightName:rightName];
}

- (IBAction)displaySystemPreferencesRight:(id)sender {
	[rightChooser selectItemAtIndex:[[rightChooser dataSource] comboBox:rightChooser indexOfItemWithStringValue:_systemPreferencesRight]];
	[self updateOutlineViewWithSelectionOfComboBox:rightChooser];
}
- (IBAction)refreshView:(id)sender {
    [self updateOutlineViewWithRightName:_displayedRight];
}
- (IBAction)exportRightDefinition:(id)sender {
	NSSavePanel *savePanel = [NSSavePanel savePanel];
	[savePanel setRequiredFileType:@"plist"];
	[savePanel setPrompt:@"Export"];
		
	// Display Save Sheet
	[savePanel beginSheetForDirectory:nil 
								 file:[NSString stringWithFormat:@"%@.plist", _displayedRight] 
					   modalForWindow:inspectorWindow 
						modalDelegate:self 
					   didEndSelector:@selector(savePanelDidEnd:returnCode:contextInfo:) 
						  contextInfo:[_displayedRight copy]
	 ];
}
- (void)savePanelDidEnd:(NSSavePanel *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
	NSString *rightName = [(id)contextInfo autorelease];
	
	if (returnCode != NSOKButton) return;
	NSString *destinationFile = [sheet filename];
		
	NSDictionary *rightDefinition = [self rightDefinitionByName:rightName]; // returns nil if not found
	if (!rightDefinition) {
		NSRunAlertPanel(@"Could not export Right Definition", @"The Right Definition could not be exported because the definition is empty", nil, nil, nil);
		return;
	}
	[rightDefinition writeToFile:destinationFile atomically:YES];
}
- (IBAction)comboBoxAction:(NSComboBox *)sender {
	[self updateOutlineViewWithSelectionOfComboBox:sender];
}

- (void)dealloc {
	[[rightChooser dataSource] release];
	[[rightView dataSource] release];
	[_rightsDB release];
	[_displayedRight release];
	[_systemPreferencesRight release];
	[super dealloc];
}

@end
