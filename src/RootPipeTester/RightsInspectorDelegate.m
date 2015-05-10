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



@implementation RightsInspectorDelegate

- (id)init {
	if ((self = [super init])) {
		_rightsDB = nil;
		_displayedRight = nil;
	}
	return self;
}

- (BOOL)loadPolicyDBFromPath:(NSString *)path {
	[_rightsDB release];
	_rightsDB = [(([(_rightsDB = [NSDictionary dictionaryWithContentsOfFile:path]) objectForKey:@"rights"]) ?: _rightsDB) retain]; // 10.2.x doesn't have a rights subkey
	
	return ([_rightsDB isKindOfClass:[NSDictionary class]] && [_rightsDB count] > 0);
}

- (void)awakeFromNib {
	
	// Load Policy Database
	if (![self loadPolicyDBFromPath:POLICY_DATABASE_FILE]) { NSLog(@"Error while loading Policy DB"); }
	
	// Initialise Combo Box Values
	[rightChooser setDataSource:[[RPTRightsDataSource alloc] initWithRightsDB:_rightsDB]];
	[rightChooser reloadData];
	
	// Select "system.preferences" by default
	[rightChooser selectItemAtIndex:[[rightChooser dataSource] comboBox:rightChooser indexOfItemWithStringValue:@"system.preferences"]];
	[self updateOutlineViewWithSelectionOfComboBox:rightChooser];
}

- (NSDictionary *)rightDefinitionByName:(NSString *)name {
	NSDictionary *rightDefinition = nil;
	OSStatus (*rightget)(const char *, CFDictionaryRef *) = CFBundleGetFunctionPointerForName(CFBundleCreate(kCFAllocatorDefault, (CFURLRef)[NSURL URLWithString:@"/System/Library/Frameworks/Security.framework"]), (CFStringRef)@"AuthorizationRightGet");
	
	if (rightget) {
		// Ask Authorization Services for the dictionary (10.3+)
		(*rightget)([name UTF8String], (CFDictionaryRef *)&rightDefinition); // rightDefinition is autoreleased
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

- (IBAction)refreshView:(NSButton *)sender {
    [self updateOutlineViewWithRightName:_displayedRight];
}
- (IBAction)comboBoxAction:(NSComboBox *)sender {
	[self updateOutlineViewWithSelectionOfComboBox:sender];
}

- (void)dealloc {
	[[rightChooser dataSource] release];
	[[rightView dataSource] release];
	[_rightsDB release];
	[_displayedRight release];
	[super dealloc];
}

@end
