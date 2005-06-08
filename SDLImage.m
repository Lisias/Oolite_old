/*
 * This class encapsulates an SDL_Surface pointer so it can be stored in
 * an Objective-C collection.
 *
 * David Taylor 23-May-2005
 */
#include "SDLImage.h"

@implementation SDLImage

- (id) initWithSurface: (SDL_Surface *)surface
{
	self = [super init];
	m_surface = surface;
	m_size.width = surface->w;
	m_size.height = surface->h;
	return self;
}

- (SDL_Surface *) surface
{
	return m_surface;
}

- (NSSize) size
{
	return m_size;
}

@end
