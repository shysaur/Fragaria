/*
 MGSFragaria
 Written by Jonathan Mitchell, jonathan@mugginsoft.com
 Find the latest version at https://github.com/mugginsoft/Fragaria

 Smultron version 3.6b1, 2009-09-12
 Written by Peter Borg, pgw3@mac.com
 Find the latest version at http://smultron.sourceforge.net

 Copyright 2004-2009 Peter Borg

 Licensed under the Apache License, Version 2.0 (the "License"); you may not use
 this file except in compliance with the License. You may obtain a copy of the
 License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software distributed
 under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 CONDITIONS OF ANY KIND, either express or implied. See the License for the
 specific language governing permissions and limitations under the License.
 */

#import "MGSFragariaFramework.h"
#import "MGSFragaria.h"
#import "MGSFragariaPrivate.h"
#import "SMLTextViewPrivate.h"


static BOOL CharacterIsBrace(unichar c)
{
    NSCharacterSet *braces = [NSCharacterSet characterSetWithCharactersInString:@"()[]{}<>"];
    return [braces characterIsMember:c];
}


static BOOL CharacterIsClosingBrace(unichar c)
{
    NSCharacterSet *braces = [NSCharacterSet characterSetWithCharactersInString:@")]}>"];
    return [braces characterIsMember:c];
}


static unichar OpeningBraceForClosingBrace(unichar c)
{
    switch (c) {
        case ')': return '(';
        case ']': return '[';
        case '}': return '{';
        case '>': return '<';
    }
    return 0;
}


static unichar ClosingBraceForOpeningBrace(unichar c)
{
    switch (c) {
        case '(': return ')';
        case '[': return ']';
        case '{': return '}';
        case '<': return '>';
    }
    return 0;
}


#pragma mark - Class Extension
@interface SMLTextView()

@property (strong) NSColor *pageGuideColour;

@end


static void *LineHighlightingPrefChanged = &LineHighlightingPrefChanged;


#pragma mark - Implementation

@implementation SMLTextView {

    BOOL isDragging;
    NSPoint startPoint;
    NSPoint startOrigin;

    CGFloat pageGuideX;

    NSRect currentLineRect;

    NSTimer *autocompleteWordsTimer;
}

@synthesize lineWrap = _lineWrap;
@synthesize pageGuideColour = _pageGuideColour;
@synthesize showsPageGuide = _showsPageGuide;


#pragma mark - Properties - Internal

/*
 * @property fragaria
 * (synthesized)
 */

/*
 * @property inspectedCharacterIndexes
 * (synthesized)
 */


#pragma mark - Properties - Appearance and Behaviours

/*
 * @property currentLineHighlightColour
 * (synthesized)
 */
- (void)setCurrentLineHighlightColour:(NSColor *)currentLineHighlightColour
{
    _currentLineHighlightColour = currentLineHighlightColour;
    currentLineRect = [self lineHighlightingRect];
    [self setNeedsDisplayInRect:currentLineRect];
}


/*
 * @property highlightCurrentLine
 */
- (void)setHighlightCurrentLine:(BOOL)highlightCurrentLine
{
    [self setNeedsDisplayInRect:currentLineRect];
    _highlightCurrentLine = highlightCurrentLine;
    currentLineRect = [self lineHighlightingRect];
    [self setNeedsDisplayInRect:currentLineRect];
}


/*
 * @property insertionPointColor
 */
- (void)setInsertionPointColor:(NSColor *)insertionPointColor
{
    [super setInsertionPointColor:insertionPointColor];
    [self configurePageGuide];

}

- (NSColor *)insertionPointColor
{
    return [super insertionPointColor];
}


/*
 * @property lineWrap
 *   see /developer/examples/appkit/TextSizingExample
 */
- (void)setLineWrap:(BOOL)value
{
    _lineWrap = value;
    [self updateLineWrap];
}


/*
 * @property pageGuideColumn
 */
- (void)setPageGuideColumn:(NSInteger)pageGuideColumn
{
    _pageGuideColumn = pageGuideColumn;
    [self configurePageGuide];
}


/*
 * @property showsPageGuide
 */
- (void)setShowsPageGuide:(BOOL)showsPageGuide
{
    _showsPageGuide = showsPageGuide;
    [self configurePageGuide];
}

- (BOOL)showsPageGuide
{
    return _showsPageGuide;
}


/*
 * @property tabWidth
 */
- (void)setTabWidth:(NSInteger)tabWidth
{
    _tabWidth = tabWidth;

    // Set the width of every tab by first checking the size of the tab in spaces in the current font,
    // and then remove all tabs that sets automatically and then set the default tab stop distance.
    NSMutableString *sizeString = [NSMutableString string];
    NSInteger numberOfSpaces = _tabWidth;
    while (numberOfSpaces--) {
        [sizeString appendString:@" "];
    }
    NSDictionary *sizeAttribute = [self typingAttributes];
    CGFloat sizeOfTab = [sizeString sizeWithAttributes:sizeAttribute].width;

    NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];

    NSArray *array = [style tabStops];
    for (id item in array) {
        [style removeTabStop:item];
    }
    [style setDefaultTabInterval:sizeOfTab];
    
    NSMutableDictionary *attributes = [[self typingAttributes] mutableCopy];
    [attributes setObject:style forKey:NSParagraphStyleAttributeName];
    [self setTypingAttributes:attributes];
    
    [[self textStorage] addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0,[[self textStorage] length])];
}


/*
 * @property textColor
 */
- (void)setTextColor:(NSColor *)textColor
{
    [super setTextColor:textColor];
    [self configurePageGuide];

}

- (NSColor *)textColor
{
    return [super textColor];
}


/*
 * @property textFont
 */
- (void)setTextFont:(NSFont *)textFont
{
    /* setFont: also updates our typing attributes */
    [self setFont:textFont];
    [self configurePageGuide];
    [self setTabWidth:_tabWidth];
}

- (NSFont *)textFont
{
    return [[self typingAttributes] objectForKey:NSFontAttributeName];
}


/*
 * -(void)setLayoutOrientation:
 */
- (void)setLayoutOrientation:(NSTextLayoutOrientation)theOrientation
{
    /* Currently, vertical layout breaks the ruler */
    [super setLayoutOrientation:NSTextLayoutOrientationHorizontal];
}


#pragma mark - Strings - Properties and Methods


/*
 * @property string:
 */
- (void)setString:(NSString *)aString
{
    [super setString:aString];
    [[NSNotificationCenter defaultCenter] postNotificationName:NSTextDidChangeNotification object:self];
}


/*
 * @property attributedString:
 */
- (void)setAttributedString:(NSAttributedString *)attrString
{
    NSTextStorage *textStorage = [self textStorage];
    [textStorage setAttributedString:attrString];
}

/*
 * - setString:options:
 */
- (void)setString:(NSString *)aString options:(NSDictionary *)options
{
    NSRange all = NSMakeRange(0, [self.textStorage length]);
    [self replaceCharactersInRange:all withString:aString options:options];
}


/*
 * - setAttributedString:options:
 */
- (void)setAttributedString:(NSAttributedString *)text options:(NSDictionary *)options
{
    BOOL undo = [[options objectForKey:@"undo"] boolValue];

    NSTextStorage *textStorage = [self textStorage];

    if ([self isEditable] && undo) {

        /*

         see http://www.cocoabuilder.com/archive/cocoa/179875-exponent-action-in-nstextview-subclass.html
         entitled: Re: "exponent" action in NSTextView subclass (SOLVED)

         This details how to make programmatic changes to the textStorage object.

         */

        /*

         code here reflects what occurs in - setString:options:

         may be over complicated

         */
        NSRange all = NSMakeRange(0, [textStorage length]);
        BOOL textIsEmpty = ([textStorage length] == 0 ? YES : NO);

        if ([self shouldChangeTextInRange:all replacementString:[text string]]) {
            [textStorage beginEditing];
            [textStorage setAttributedString:text];
            [textStorage endEditing];

            // reset the default font if text was empty as the font gets reset to system default.
            if (textIsEmpty) {
                [self setFont:self.textFont];
            }

            [self didChangeText];

            NSUndoManager *undoManager = [self undoManager];

            // TODO: this doesn't seem to be having the desired effect
            [undoManager setActionName:NSLocalizedString(@"Content Change", @"undo content change")];

        }
    } else {
        [self setAttributedString:text];
    }
}


/*
 * - replaceCharactersInRange:withString:options
 */
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)text options:(NSDictionary *)options
{
    BOOL undo = [[options objectForKey:@"undo"] boolValue];
    BOOL textViewWasEmpty = ([self.textStorage length] == 0 ? YES : NO);

    if ([self isEditable] && undo) {

        // this sequence will be registered with the undo manager
        if ([self shouldChangeTextInRange:range replacementString:text]) {

            // modify he text storage
            [self.textStorage beginEditing];
            [self.textStorage replaceCharactersInRange:range withString:text];
            [self.textStorage endEditing];

            // reset the default font if text was empty as the font gets reset to system default.
            if (textViewWasEmpty) {
                [self setFont:self.textFont];
            }

            // TODO: this doesn't seem to be having the desired effect
            NSUndoManager *undoManager = [self undoManager];
            [undoManager setActionName:NSLocalizedString(@"Content Change", @"undo content change")];

            // complete the text change operation
            [self didChangeText];
        }
    } else if (textViewWasEmpty) {
        // this operation will not be registered with the undo manager
        [self setString:text];
    } else {
        // this operation will not be registered with the undo manager
        [self.textStorage replaceCharactersInRange:range withString:text];;
    }
}


#pragma mark - Instance methods - Intializers and Setup

/*
 * - initWithFrame:fragaria:
 */

- (id)initWithFrame:(NSRect)frame fragaria:(MGSFragaria *)fragaria
{
    if ((self = [super initWithFrame:frame])) {
        SMLLayoutManager *layoutManager = [[SMLLayoutManager alloc] init];
        [[self textContainer] replaceLayoutManager:layoutManager];

        _fragaria = fragaria;
        _interfaceController = [[MGSExtraInterfaceController alloc] init];
        [_interfaceController setCompletionTarget:self];
        
        _syntaxColouring = [[SMLSyntaxColouring alloc] initWithLayoutManager:layoutManager];

        [self setDefaults];

        // set initial line wrapping
        _lineWrap = YES;
        isDragging = NO;
        [self updateLineWrap];
    }
    return self;
}


/*
 * - initWithFrame:
 */
- (id)initWithFrame:(NSRect)frame
{
    return [self initWithFrame:frame fragaria:nil];
}


/*
 * - setDefaults
 */
- (void)setDefaults
{

    [self setVerticallyResizable:YES];
    [self setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    [self setAutoresizingMask:NSViewWidthSizable];
    [self setAllowsUndo:YES];
    if ([self respondsToSelector:@selector(setUsesFindBar:)])
    {
        [self setUsesFindBar:YES];
        [self setIncrementalSearchingEnabled:NO];
    }
    else
    {
        [self setUsesFindPanel:YES];
    }

    [self setAllowsDocumentBackgroundColorChange:NO];
    [self setRichText:NO];
    [self setImportsGraphics:NO];
    [self setUsesFontPanel:NO];

    NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:[self frame] options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveWhenFirstResponder) owner:self userInfo:nil];
    [self addTrackingArea:trackingArea];

    [self configurePageGuide];
}


#pragma mark - Menu Item Validation

/*
 * - validateMenuItems
 */
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if ([menuItem action] == @selector(toggleAutomaticDashSubstitution:))
        return NO;
    if ([menuItem action] == @selector(toggleAutomaticQuoteSubstitution:))
        return NO;
    if ([menuItem action] == @selector(changeLayoutOrientation:))
        return NO;
    return [super validateMenuItem:menuItem];
}


#pragma mark - Copy and paste

/*
 * - paste
 */
-(void)paste:(id)sender
{
    // let super paste
    [super paste:sender];

    // add the NSTextView  to the info dict
    NSDictionary *info = @{@"NSTextView": self};

    // send paste notification
    NSNotification *note = [NSNotification notificationWithName:@"MGSTextDidPasteNotification" object:self userInfo:info];
    [[NSNotificationCenter defaultCenter] postNotification:note];

    // inform delegate of Fragaria paste
    if ([self.delegate respondsToSelector:@selector(mgsTextDidPaste:)]) {
        [(id)self.delegate mgsTextDidPaste:note];
    }
}


#pragma mark - Drawing

/*
 * - isOpaque
 */
- (BOOL)isOpaque
{
    return YES;
}


/*
 * - drawRect:
 */
- (void)drawRect:(NSRect)rect
{
    const NSRect *dirtyRects;
    NSRange recolourRange;
    NSInteger rectCount, i;
    
    [self getRectsBeingDrawn:&dirtyRects count:&rectCount];
    
    for (i=0; i<rectCount; i++) {
        recolourRange = [[self layoutManager] glyphRangeForBoundingRect:dirtyRects[i] inTextContainer:[self textContainer]];
        recolourRange = [[self layoutManager] characterRangeForGlyphRange:recolourRange actualGlyphRange:NULL];
        [self.syntaxColouring recolourRange:recolourRange];
    }
    
    [super drawRect:rect];
    
    if (self.showsPageGuide == YES) {
        NSRect bounds = [self bounds];
        if ([self needsToDrawRect:NSMakeRect(pageGuideX, 0, 1, bounds.size.height)] == YES) { // So that it doesn't draw the line if only e.g. the cursor updates
            [self.pageGuideColour set];
            [NSBezierPath strokeRect:NSMakeRect(pageGuideX, 0, 0, bounds.size.height)];
        }
    }
}


#pragma mark - Line Highlighting


/*
 * - drawViewBackgroundInRect:
 */
- (void)drawViewBackgroundInRect:(NSRect)rect
{
    [super drawViewBackgroundInRect:rect];
    
    if ([self needsToDrawRect:currentLineRect]) {
        [self.currentLineHighlightColour set];
        [NSBezierPath fillRect:currentLineRect];
    }
}


/*
 * - lineHighlightingRect
 */
- (NSRect)lineHighlightingRect
{
    NSMutableString *ms;
    NSRange selRange, lineRange, multipleLineRange;
    NSRect lineRect;

    if (!_highlightCurrentLine) return NSZeroRect;

    selRange = [self selectedRange];
    ms = [[self textStorage] mutableString];
    multipleLineRange = [ms lineRangeForRange:selRange];
    lineRange = [ms lineRangeForRange:NSMakeRange(selRange.location, 0)];
    if (NSEqualRanges(lineRange, multipleLineRange)) {
        lineRange = [[self layoutManager] glyphRangeForCharacterRange:lineRange actualCharacterRange:NULL];
        lineRect = [[self layoutManager] boundingRectForGlyphRange:lineRange inTextContainer:[self textContainer]];
        lineRect.origin.x = 0;
        lineRect.size.width = [self bounds].size.width;
        return lineRect;
    }
    return NSZeroRect;
}


/*
 * - setSelectedRanges:
 */
- (void)setSelectedRanges:(NSArray *)selectedRanges
{
    [self setNeedsDisplayInRect:currentLineRect];
    [super setSelectedRanges:selectedRanges];
    currentLineRect = [self lineHighlightingRect];
    [self setNeedsDisplayInRect:currentLineRect];
}


/*
 * - setSelectedRange:
 */
- (void)setSelectedRange:(NSRange)selectedRange
{
    [self setNeedsDisplayInRect:currentLineRect];
    [super setSelectedRange:selectedRange];
    currentLineRect = [self lineHighlightingRect];
    [self setNeedsDisplayInRect:currentLineRect];
}


/*
 * - setSelectedRange:affinity:stillSelecting:
 */
- (void)setSelectedRange:(NSRange)charRange affinity:(NSSelectionAffinity)affinity stillSelecting:(BOOL)stillSelectingFlag
{
    [self setNeedsDisplayInRect:currentLineRect];
    [super setSelectedRange:charRange affinity:affinity stillSelecting:stillSelectingFlag];
    currentLineRect = [self lineHighlightingRect];
    [self setNeedsDisplayInRect:currentLineRect];
}


/*
 * - setSelectedRanges:affinity:stillSelecting:
 */
- (void)setSelectedRanges:(NSArray *)ranges affinity:(NSSelectionAffinity)affinity stillSelecting:(BOOL)stillSelectingFlag
{
    [self setNeedsDisplayInRect:currentLineRect];
    [super setSelectedRanges:ranges affinity:affinity stillSelecting:stillSelectingFlag];
    currentLineRect = [self lineHighlightingRect];
    [self setNeedsDisplayInRect:currentLineRect];
}


/*
 * - setFrame:
 */
- (void)setFrame:(NSRect)bounds
{
    [self setNeedsDisplayInRect:currentLineRect];
    [super setFrame:bounds];
    currentLineRect = [self lineHighlightingRect];
    [self setNeedsDisplayInRect:currentLineRect];
}


#pragma mark - Mouse event handling


/*
 * - flagsChanged:
 */
- (void)flagsChanged:(NSEvent *)theEvent
{
    [super flagsChanged:theEvent];

    if (([theEvent modifierFlags] & NSAlternateKeyMask) && ([theEvent modifierFlags] & NSCommandKeyMask)) {
        isDragging = YES;
        [[NSCursor openHandCursor] set];
    } else {
        isDragging = NO;
        [[NSCursor IBeamCursor] set];
    }
}


/*
 * - mouseDown:
 */
- (void)mouseDown:(NSEvent *)theEvent
{
    if (([theEvent modifierFlags] & NSAlternateKeyMask) && ([theEvent modifierFlags] & NSCommandKeyMask)) { // If the option and command keys are pressed, change the cursor to grab-cursor
        startPoint = [theEvent locationInWindow];
        startOrigin = [[[self enclosingScrollView] contentView] documentVisibleRect].origin;
        isDragging = YES;
    } else {
        [super mouseDown:theEvent];
    }
}


/*
 * - mouseDragged:
 */
- (void)mouseDragged:(NSEvent *)theEvent
{
    if (isDragging) {
        [self scrollPoint:NSMakePoint(startOrigin.x - ([theEvent locationInWindow].x - startPoint.x) * 3, startOrigin.y + ([theEvent locationInWindow].y - startPoint.y) * 3)];
    } else {
        [super mouseDragged:theEvent];
    }
}


/*
 * - mouseMoved:
 */
- (void)mouseMoved:(NSEvent *)theEvent
{
    [super mouseMoved:theEvent];
    if (isDragging)
        [[NSCursor openHandCursor] set];
}


/*
 * - menuForEvent:
 */
- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{

    NSMenu *menu = [super menuForEvent:theEvent];

    return menu;

    // TODO: consider what menu behaviour is appropriate
    /*
     NSArray *array = [menu itemArray];
     for (id oldMenuItem in array) {
     if ([oldMenuItem tag] == -123457) {
     [menu removeItem:oldMenuItem];
     }
     }

     [menu insertItem:[NSMenuItem separatorItem] atIndex:0];

     NSEnumerator *collectionEnumerator = [[SMLBasic fetchAll:@"SnippetCollectionSortKeyName"] reverseObjectEnumerator];
     for (id collection in collectionEnumerator) {
     if ([collection valueForKey:@"name"] == nil) {
     continue;
     }
     NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[collection valueForKey:@"name"] action:nil keyEquivalent:@""];
     [menuItem setTag:-123457];
     NSMenu *subMenu = [[NSMenu alloc] init];

     NSMutableArray *array = [NSMutableArray arrayWithArray:[[collection mutableSetValueForKey:@"snippets"] allObjects]];
     [array sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
     for (id snippet in array) {
     if ([snippet valueForKey:@"name"] == nil) {
     continue;
     }
     NSString *keyString;
     if ([snippet valueForKey:@"shortcutMenuItemKeyString"] != nil) {
     keyString = [snippet valueForKey:@"shortcutMenuItemKeyString"];
     } else {
     keyString = @"";
     }
     NSMenuItem *subMenuItem = [[NSMenuItem alloc] initWithTitle:[snippet valueForKey:@"name"] action:@selector(snippetShortcutFired:) keyEquivalent:@""];
     [subMenuItem setTarget:[SMLToolsMenuController sharedInstance]];
     [subMenuItem setRepresentedObject:snippet];
     [subMenu insertItem:subMenuItem atIndex:0];
     }

     [menuItem setSubmenu:subMenu];
     [menu insertItem:menuItem atIndex:0];
     }

     return menu;
     */
}


#pragma mark - Tab and page guide handling

/*
 * - insertTab:
 */
- (void)insertTab:(id)sender
{
    BOOL shouldShiftText = NO;

    if ([self selectedRange].length > 0) { // Check to see if the selection is in the text or if it's at the beginning of a line or in whitespace; if one doesn't do this one shifts the line if there's only one suggestion in the auto-complete
        NSRange rangeOfFirstLine = [[self string] lineRangeForRange:NSMakeRange([self selectedRange].location, 0)];
        NSUInteger firstCharacterOfFirstLine = rangeOfFirstLine.location;
        while ([[self string] characterAtIndex:firstCharacterOfFirstLine] == ' ' || [[self string] characterAtIndex:firstCharacterOfFirstLine] == '\t') {
            firstCharacterOfFirstLine++;
        }
        if ([self selectedRange].location <= firstCharacterOfFirstLine) {
            shouldShiftText = YES;
        }
    }

    if (shouldShiftText) {
        [self shiftRight:nil];
    } else if (self.indentWithSpaces) {
        NSMutableString *spacesString = [NSMutableString string];
        NSInteger numberOfSpacesPerTab = self.tabWidth;
        if (self.useTabStops) {
            NSInteger locationOnLine = [self selectedRange].location - [[self string] lineRangeForRange:[self selectedRange]].location;
            if (numberOfSpacesPerTab != 0) {
                NSInteger numberOfSpacesLess = locationOnLine % numberOfSpacesPerTab;
                numberOfSpacesPerTab = numberOfSpacesPerTab - numberOfSpacesLess;
            }
        }
        while (numberOfSpacesPerTab--) {
            [spacesString appendString:@" "];
        }

        [self insertText:spacesString];
    } else if ([self selectedRange].length > 0) { // If there's only one word matching in auto-complete there's no list but just the rest of the word inserted and selected; and if you do a normal tab then the text is removed so this will put the cursor at the end of that word
        [self setSelectedRange:NSMakeRange(NSMaxRange([self selectedRange]), 0)];
    } else {
        [super insertTab:sender];
    }
}



#pragma mark - Text handling

/*
 * - shouldChangeTextInRanges:replacementStrings
 */
- (BOOL)shouldChangeTextInRanges:(NSArray *)affectedRanges replacementStrings:(NSArray *)replacementStrings
{
    BOOL res;
    NSArray *sortedRanges;
    NSValue *rangeVal;
    NSRange range;
    NSInteger i, newLen;
    NSMutableIndexSet *insp;

    res = [super shouldChangeTextInRanges:affectedRanges replacementStrings:replacementStrings];
    insp = self.syntaxColouring.inspectedCharacterIndexes;
    
    if (!affectedRanges)
        [insp removeAllIndexes];
    else {
        sortedRanges = [affectedRanges sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            NSRange r1, r2;
            r1 = [obj1 rangeValue];
            r2 = [obj2 rangeValue];
            /* reverse sorting */
            if (r1.location > r2.location)
                return NSOrderedAscending;
            if (r1.location == r2.location)
                return NSOrderedSame;
            return NSOrderedDescending;
        }];
        for (rangeVal in sortedRanges) {
            i = [affectedRanges indexOfObject:rangeVal];
            newLen = [[replacementStrings objectAtIndex:i] length];
            /* This is not really needed, but it allows for better edit coalescing */
            range = [[self string] lineRangeForRange:[rangeVal rangeValue]];
            [insp removeIndexesInRange:range];
            [insp shiftIndexesStartingAtIndex:range.location by:(newLen - range.length)];
            [self.syntaxColouring invalidateVisibleRangeOfTextView:self];
        }
    }
    return res;
}


/*
 * - insertText:
 */
- (void)insertText:(NSString *)aString
{
    /* AppKit Bug: when inserting an emoji (for example by double-clicking it
     * in the character set panel) an NSMutableAttributedString is passed to
     * insertText instead of an NSString. This works around this by making the
     * attributed string an NSString again. */
    if ([aString isKindOfClass:[NSAttributedString class]]){
        aString = [(NSAttributedString *)aString string];
    }

    if ([aString isEqualToString:@"}"] && self.indentNewLinesAutomatically && self.indentBracesAutomatically) {
        [self shiftBackToLastOpenBrace];
    }

    [super insertText:aString];

    if ([aString isEqualToString:@"("] && self.insertClosingParenthesisAutomatically) {
        [self insertStringAfterInsertionPoint:@")"];
    } else if ([aString isEqualToString:@"{"] && self.insertClosingBraceAutomatically) {
        [self insertStringAfterInsertionPoint:@"}"];
    }

    if ([aString length] == 1 && self.showsMatchingBraces) {
        if (CharacterIsClosingBrace([aString characterAtIndex:0])) {
            [self showBraceMatchingBrace:[aString characterAtIndex:0]];
        }
    }

    if (self.autoCompleteEnabled)
        [self scheduleAutocomplete];
}


/*
 * - insertStringAfterInsertionPoint
 */
- (void)insertStringAfterInsertionPoint:(NSString*)string
{
    NSRange selectedRange = [self selectedRange];
    if ([self shouldChangeTextInRange:selectedRange replacementString:string]) {
        [self replaceCharactersInRange:selectedRange withString:string];
        [self didChangeText];
        [self setSelectedRange:NSMakeRange(selectedRange.location, 0)];
    }
}


/*
 * - findBeginningOfNestedBlock:openedByCharacter:closedByCharacter:
 */
- (NSInteger)findBeginningOfNestedBlock:(NSInteger)charIdx openedByCharacter:(unichar)open closedByCharacter:(unichar)close
{
    NSInteger skipMatchingBrace = 0;
    NSString *completeString = [self string];
    unichar characterToCheck;

    while (charIdx--) {
        characterToCheck = [completeString characterAtIndex:charIdx];
        if (characterToCheck == open) {
            if (!skipMatchingBrace) {
                return charIdx;
            } else {
                skipMatchingBrace--;
            }
        } else if (characterToCheck == close) {
            skipMatchingBrace++;
        }
    }
    return NSNotFound;
}


/*
 * - findEndOfNestedBlock:openedByCharacter:closedByCharacter:
 */
- (NSInteger)findEndOfNestedBlock:(NSInteger)charIdx openedByCharacter:(unichar)open closedByCharacter:(unichar)close
{
    NSInteger skipMatchingBrace = 0;
    NSString *completeString = [self string];
    NSInteger lengthOfString = [completeString length];
    unichar characterToCheck;

    while (++charIdx < lengthOfString) {
        characterToCheck = [completeString characterAtIndex:charIdx];
        if (characterToCheck == close) {
            if (!skipMatchingBrace) {
                return charIdx;
            } else {
                skipMatchingBrace--;
            }
        } else if (characterToCheck == open) {
            skipMatchingBrace++;
        }
    }
    return NSNotFound;
}


/*
 * - showBraceMatchingBrace:
 */
- (void)showBraceMatchingBrace:(unichar)characterToCheck;
{
    NSInteger cursorLocation;
    unichar matchingBrace;

    matchingBrace = OpeningBraceForClosingBrace(characterToCheck);

    cursorLocation = [self selectedRange].location - 1;
    if (cursorLocation < 0) return;

    cursorLocation = [self findBeginningOfNestedBlock:cursorLocation
                                    openedByCharacter:matchingBrace closedByCharacter:characterToCheck];
    if (cursorLocation != NSNotFound)
        [self showFindIndicatorForRange:NSMakeRange(cursorLocation, 1)];
    else
        NSBeep();
}


/*
 * - shiftBackToLastOpenBrace
 */
- (void)shiftBackToLastOpenBrace
{
    NSString *completeString = [self string];
    NSInteger lineLocation = [self selectedRange].location;
    NSCharacterSet *whitespaceCharacterSet = [NSCharacterSet whitespaceCharacterSet];
    NSRange currentLineRange = [completeString lineRangeForRange:NSMakeRange(lineLocation, 0)];
    NSInteger lineStart = currentLineRange.location;

    // If there are any characters before } on the line, don't indent
    NSInteger i = lineLocation;
    while (--i >= lineStart) {
        if (![whitespaceCharacterSet characterIsMember:[completeString characterAtIndex:i]])
            return;
    }

    // Find the matching closing brace
    NSInteger location;
    location = [self findBeginningOfNestedBlock:lineLocation openedByCharacter:'{' closedByCharacter:'}'];
    if (location == NSNotFound) return;

    // If we have found the opening brace check first how much
    // space is in front of that line so the same amount can be
    // inserted in front of the new line.
    // If we found that space, replace the indenting of our line with the indenting from the opening brace line.
    // Otherwise just remove all the whitespace before the closing brace.
    NSString *openingBraceLineWhitespaceString;
    NSRange openingBraceLineRange = [completeString lineRangeForRange:NSMakeRange(location, 0)];
    NSString *openingBraceLine = [completeString substringWithRange:openingBraceLineRange];
    NSScanner *openingLineScanner = [[NSScanner alloc] initWithString:openingBraceLine];
    [openingLineScanner setCharactersToBeSkipped:nil];

    BOOL found = [openingLineScanner scanCharactersFromSet:whitespaceCharacterSet intoString:&openingBraceLineWhitespaceString];
    if (!found) {
        openingBraceLineWhitespaceString = @"";
    }

    // Replace the beginning of the line with the new indenting
    NSRange startInsertLineRange;
    startInsertLineRange = NSMakeRange(currentLineRange.location, lineLocation - currentLineRange.location);
    if ([self shouldChangeTextInRange:startInsertLineRange replacementString:openingBraceLineWhitespaceString]) {
        [self replaceCharactersInRange:startInsertLineRange withString:openingBraceLineWhitespaceString];
        [self didChangeText];
        [self setSelectedRange:NSMakeRange(currentLineRange.location + [openingBraceLineWhitespaceString length], 0)];
    }
}


/*
 * - insertNewline:
 */
- (void)insertNewline:(id)sender
{
    [super insertNewline:sender];

    // If we should indent automatically, check the previous line and scan all the whitespace at the beginning of the line into a string and insert that string into the new line
    NSString *lastLineString = [[self string] substringWithRange:[[self string] lineRangeForRange:NSMakeRange([self selectedRange].location - 1, 0)]];
    if (self.indentNewLinesAutomatically) {
        NSString *previousLineWhitespaceString;
        NSScanner *previousLineScanner = [[NSScanner alloc] initWithString:[[self string] substringWithRange:[[self string] lineRangeForRange:NSMakeRange([self selectedRange].location - 1, 0)]]];
        [previousLineScanner setCharactersToBeSkipped:nil];
        if ([previousLineScanner scanCharactersFromSet:[NSCharacterSet whitespaceCharacterSet] intoString:&previousLineWhitespaceString]) {
            [self insertText:previousLineWhitespaceString];
        }

        if (self.indentBracesAutomatically) {
            NSCharacterSet *characterSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
            NSInteger idx = [lastLineString length];
            while (idx--) {
                if ([characterSet characterIsMember:[lastLineString characterAtIndex:idx]]) {
                    continue;
                }
                if ([lastLineString characterAtIndex:idx] == '{') {
                    [self insertTab:nil];
                }
                break;
            }
        }
    }
}


#pragma mark - Selection handling

/*
 * - selectionRangeForProposedRange:granularity:
 */
- (NSRange)selectionRangeForProposedRange:(NSRange)proposedSelRange granularity:(NSSelectionGranularity)granularity
{
    // If it's not a mouse event return unchanged
    NSEventType eventType = [[NSApp currentEvent] type];
    if (eventType != NSLeftMouseDown && eventType != NSLeftMouseUp) {
        return [super selectionRangeForProposedRange:proposedSelRange granularity:granularity];
    }

    if (granularity != NSSelectByWord || [[self string] length] == proposedSelRange.location || [[NSApp currentEvent] clickCount] != 2) { // If it's not a double-click return unchanged
        return [super selectionRangeForProposedRange:proposedSelRange granularity:granularity];
    }

    NSUInteger location = [super selectionRangeForProposedRange:proposedSelRange granularity:NSSelectByCharacter].location;
    NSInteger originalLocation = location;

    NSString *completeString = [self string];
    unichar characterToCheck = [completeString characterAtIndex:location];
    NSUInteger lengthOfString = [completeString length];
    if (lengthOfString == proposedSelRange.location) { // To avoid crash if a double-click occurs after any text
        return [super selectionRangeForProposedRange:proposedSelRange granularity:granularity];
    }


    BOOL triedToMatchBrace = NO;
    unichar matchingBrace;

    if (CharacterIsBrace(characterToCheck)) {
        triedToMatchBrace = YES;
        if (CharacterIsClosingBrace(characterToCheck)) {
            matchingBrace = OpeningBraceForClosingBrace(characterToCheck);
            location = [self findBeginningOfNestedBlock:location openedByCharacter:matchingBrace closedByCharacter:characterToCheck];
            if (location != NSNotFound)
                return NSMakeRange(location, originalLocation - location + 1);
            NSBeep();
        } else {
            matchingBrace = ClosingBraceForOpeningBrace(characterToCheck);
            location = [self findEndOfNestedBlock:location openedByCharacter:characterToCheck closedByCharacter:matchingBrace];
            if (location != NSNotFound)
                return NSMakeRange(originalLocation, location - originalLocation + 1);
            NSBeep();
        }
    }

    // If it has a found a "starting" brace but not found a match, a double-click should only select the "starting" brace and not what it usually would select at a double-click
    if (triedToMatchBrace) {
        return [super selectionRangeForProposedRange:NSMakeRange(proposedSelRange.location, 1) granularity:NSSelectByCharacter];
    } else {

        NSInteger startLocation = originalLocation;
        NSInteger stopLocation = originalLocation;
        NSInteger minLocation = [super selectionRangeForProposedRange:proposedSelRange granularity:NSSelectByWord].location;
        NSInteger maxLocation = NSMaxRange([super selectionRangeForProposedRange:proposedSelRange granularity:NSSelectByWord]);

        BOOL hasFoundSomething = NO;
        while (--startLocation >= minLocation) {
            if ([completeString characterAtIndex:startLocation] == '.' || [completeString characterAtIndex:startLocation] == ':') {
                hasFoundSomething = YES;
                break;
            }
        }

        while (++stopLocation < maxLocation) {
            if ([completeString characterAtIndex:stopLocation] == '.' || [completeString characterAtIndex:stopLocation] == ':') {
                hasFoundSomething = YES;
                break;
            }
        }

        if (hasFoundSomething == YES) {
            return NSMakeRange(startLocation + 1, stopLocation - startLocation - 1);
        } else {
            return [super selectionRangeForProposedRange:proposedSelRange granularity:granularity];
        }
    }
}


#pragma mark - Auto Completion


/*
 * - scheduleAutocomplete
 */
- (void)scheduleAutocomplete
{
    if (!autocompleteWordsTimer) {
        autocompleteWordsTimer = [NSTimer scheduledTimerWithTimeInterval:self.autoCompleteDelay
                                                                  target:self selector:@selector(autocompleteWordsTimerSelector:)
                                                                userInfo:nil repeats:NO];
    }
    [autocompleteWordsTimer setFireDate:[NSDate dateWithTimeIntervalSinceNow:self.autoCompleteDelay]];
}


/*
 * - autocompleteWordsTimerSelector:
 */
- (void)autocompleteWordsTimerSelector:(NSTimer *)theTimer
{
    NSRange selectedRange = [self selectedRange];
    NSString *completeString = [self string];
    NSUInteger stringLength = [completeString length];

    if (selectedRange.location <= stringLength && selectedRange.length == 0 && stringLength != 0) {
        if (selectedRange.location == stringLength) { // If we're at the very end of the document
            [self complete:nil];
        } else {
            unichar characterAfterSelection = [completeString characterAtIndex:selectedRange.location];
            if ([[NSCharacterSet symbolCharacterSet] characterIsMember:characterAfterSelection] || [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:characterAfterSelection] || [[NSCharacterSet punctuationCharacterSet] characterIsMember:characterAfterSelection] || selectedRange.location == stringLength) { // Don't autocomplete if we're in the middle of a word
                [self complete:nil];
            }
        }
    }
}


/*
 * - complete:
 */
- (void)complete:(id)sender
{
    /* If somebody triggers autocompletion with ESC, we don't want to trigger
     * it again in the future because of the timer */
    if (autocompleteWordsTimer) {
        [autocompleteWordsTimer invalidate];
        autocompleteWordsTimer = nil;
    }
    [super complete:sender];
}


/*
 * - rangeForUserCompletion
 */
- (NSRange)rangeForUserCompletion
{
    NSRange cursor = [self selectedRange];
    NSUInteger loc = cursor.location;

    // Check for selections (can only autocomplete when nothing is selected)
    if (cursor.length > 0)
    {
        return NSMakeRange(NSNotFound, 0);
    }

    // Cannot autocomplete on first character
    if (loc == 0)
    {
        return NSMakeRange(NSNotFound, 0);
    }

    // Create char set with characters valid for variables
    NSCharacterSet* variableChars = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVXYZ0123456789_\\"];

    NSString* text = [self string];

    // Can only autocomplete on variable names
    if (![variableChars characterIsMember:[text characterAtIndex:loc-1]])
    {
        return NSMakeRange(NSNotFound, 0);
    }

    // TODO: Check if we are in a string

    // Search backwards in string until we hit a non-variable char
    NSUInteger numChars = 1;
    NSUInteger searchLoc = loc - 1;
    while (searchLoc > 0)
    {
        if ([variableChars characterIsMember:[text characterAtIndex:searchLoc-1]])
        {
            numChars += 1;
            searchLoc -= 1;
        }
        else
        {
            break;
        }
    }

    return NSMakeRange(loc-numChars, numChars);
}


/*
 * - completionsForPartialWordRange:indexOfSelectedItem;
 */
- (NSArray*)completionsForPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)index
{
    NSMutableArray* matchArray = [NSMutableArray array];

    // use handler
    if (self.autocompleteDelegate) {

        // get all completions
        NSArray* allCompletions = [self.autocompleteDelegate completions];

        // get string to match
        NSString *matchString = [[self string] substringWithRange:charRange];

        // build array of suitable suggestions
        for (NSString* completeWord in allCompletions)
        {
            if ([completeWord rangeOfString:matchString options:NSCaseInsensitiveSearch range:NSMakeRange(0, [completeWord length])].location == 0)
            {
                [matchArray addObject:completeWord];
            }
        }
    }

    return matchArray;
}


#pragma mark - Line Wrap

/*
 * - updateLineWrap
 *   see http://developer.apple.com/library/mac/#samplecode/TextSizingExample
 *   The readme file in the above example has very good info on how to configure NSTextView instances.
 */
- (void)updateLineWrap {
    NSSize contentSize;

    // get control properties
    NSScrollView *textScrollView = [self enclosingScrollView];
    NSTextContainer *textContainer = [self textContainer];

    if (textScrollView) {
        // content view is clipview
        contentSize = [textScrollView contentSize];
    } else {
        /* scroll view may not be already there */
        contentSize = [self frame].size;
    }

    if (self.lineWrap) {
        // setup text container
        [textContainer setContainerSize:NSMakeSize(contentSize.width, CGFLOAT_MAX)];
        [textContainer setWidthTracksTextView:YES];
        [textContainer setHeightTracksTextView:NO];

        // setup text view
        [self setFrameSize:contentSize];
        [self setHorizontallyResizable: NO];
        [self setVerticallyResizable: YES];
        [self setMinSize:NSMakeSize(10, contentSize.height)];
        [self setMaxSize:NSMakeSize(10, CGFLOAT_MAX)];

        // setup scroll view
        [textScrollView setHasHorizontalScroller:NO];
    } else {

        // setup text container
        [textContainer setWidthTracksTextView:NO];
        [textContainer setHeightTracksTextView:NO];
        [textContainer setContainerSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];

        // setup text view
        [self setFrameSize:contentSize];
        [self setHorizontallyResizable: YES];
        [self setVerticallyResizable: YES];
        [self setMinSize:contentSize];
        [self setMaxSize:NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX)];

        // setup scroll view
        [textScrollView setHasHorizontalScroller:YES];
    }

    // invalidate the glyph layout
    [[self layoutManager] textContainerChangedGeometry:textContainer];

    // redraw the display and reposition scrollers
    [textScrollView reflectScrolledClipView:textScrollView.contentView];
    [textScrollView setNeedsDisplay:YES];
}


#pragma mark - Page Guide

- (void)configurePageGuide
{
    NSDictionary *sizeAttribute = [self typingAttributes];

    NSString *sizeString = @" ";
    CGFloat sizeOfCharacter = [sizeString sizeWithAttributes:sizeAttribute].width;
    pageGuideX = floor(sizeOfCharacter * (self.pageGuideColumn + 1)) - 1.5f; // -1.5 to put it between the two characters and draw only on one pixel and not two (as the system draws it in a special way), and that's also why the width above is set to zero

    NSColor *color = self.textColor;
    self.pageGuideColour = [color colorWithAlphaComponent:([color alphaComponent] / 4)]; // Use the same colour as the text but with more transparency

    [self display]; // To reflect the new values in the view
}


@end
