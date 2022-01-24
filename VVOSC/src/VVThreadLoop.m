
#import "VVThreadLoop.h"
#import "VVAssertionHandler.h"




@implementation VVThreadLoop


- (id) initWithTimeInterval:(double)i target:(id)t selector:(SEL)s	{
	if ((t==nil) || (s==nil) || (![t respondsToSelector:s]))
		return nil;
	if (self = [super init])	{
		[self generalInit];
		interval = i;
		maxInterval = 1.0;
		targetObj = t;
		targetSel = s;
		return self;
	}
	[self release];
	return nil;
}
- (id) initWithTimeInterval:(double)i	{
	if (self = [super init])	{
		[self generalInit];
		interval = i;
		return self;
	}
	[self release];
	return nil;
}
- (void) generalInit	{
	interval = 0.1;
	running = NO;
	bail = NO;
	paused = NO;
	executingCallback = NO;
	
	valLock = OS_UNFAIR_LOCK_INIT;
	
	targetObj = nil;
	targetSel = nil;
}
- (void) dealloc	{
	//NSLog(@"%s",__func__);
	[self stopAndWaitUntilDone];
	targetObj = nil;
	targetSel = nil;
	[super dealloc];
}
- (void) start	{
	//NSLog(@"%s",__func__);
	os_unfair_lock_lock(&valLock);
	if (running)	{
		os_unfair_lock_unlock(&valLock);
		return;
	}
	paused = NO;
	os_unfair_lock_unlock(&valLock);
	
	[NSThread
		detachNewThreadSelector:@selector(threadCallback)
		toTarget:self
		withObject:nil];
}
- (void) threadCallback	{
	//NSLog(@"%s",__func__);
	NSAutoreleasePool		*pool = [[NSAutoreleasePool alloc] init];
	
	USE_CUSTOM_ASSERTION_HANDLER
	
	BOOL					tmpRunning = YES;
	BOOL					tmpBail = NO;
	os_unfair_lock_lock(&valLock);
	running = YES;
	bail = NO;
	os_unfair_lock_unlock(&valLock);
	
	if (![NSThread setThreadPriority:1.0])
		NSLog(@"\terror setting thread priority to 1.0");
	
	STARTLOOP:
	@try	{
		while ((tmpRunning) && (!tmpBail))	{
			//NSLog(@"\t\tproc start");
			struct timeval		startTime;
			struct timeval		stopTime;
			double				executionTime;
			double				sleepDuration;	//	in microseconds!
			
			gettimeofday(&startTime,NULL);
			os_unfair_lock_lock(&valLock);
			if (!paused)	{
				executingCallback = YES;
				os_unfair_lock_unlock(&valLock);
				//@try	{
					//	if there's a target object, ping it (delegate-style)
					if (targetObj != nil)
						[targetObj performSelector:targetSel];
					//	else just call threadProc (subclass-style)
					else
						[self threadProc];
				//}
				//@catch (NSException *err)	{
				//	NSLog(@"%s caught exception, %@",__func__,err);
				//}
				
				os_unfair_lock_lock(&valLock);
				executingCallback = NO;
				os_unfair_lock_unlock(&valLock);
			}
			else
				os_unfair_lock_unlock(&valLock);
			
			//++runLoopCount;
			//if (runLoopCount > 4)	{
			{
				NSAutoreleasePool		*oldPool = pool;
				pool = nil;
				[oldPool release];
				pool = [[NSAutoreleasePool alloc] init];
			//	runLoopCount = 0;
			}
			
			//	figure out how long it took to run the callback
			gettimeofday(&stopTime,NULL);
			while (stopTime.tv_sec > startTime.tv_sec)	{
				--stopTime.tv_sec;
				stopTime.tv_usec = stopTime.tv_usec + 1000000;
			}
			executionTime = ((double)(stopTime.tv_usec-startTime.tv_usec))/1000000.0;
			sleepDuration = interval - executionTime;
			
			//	only sleep if duration's > 0, sleep for a max of 1 sec
			if (sleepDuration > 0)	{
				if (sleepDuration > maxInterval)
					sleepDuration = maxInterval;
				[NSThread sleepForTimeInterval:sleepDuration];
			}
			
			os_unfair_lock_lock(&valLock);
			tmpRunning = running;
			tmpBail = bail;
			os_unfair_lock_unlock(&valLock);
			//NSLog(@"\t\tproc looping");
		}
	}
	@catch (NSException *err)	{
		NSAutoreleasePool		*oldPool = pool;
		pool = nil;
		if (targetObj == nil)
			NSLog(@"\t\t%s caught exception %@ on %@",__func__,err,self);
		else
			NSLog(@"\t\t%s caught exception %@ on %@, target is %@",__func__,err,self,[targetObj class]);
		@try {
			[oldPool release];
		}
		@catch (NSException *subErr)	{
			if (targetObj == nil)
				NSLog(@"\t\t%s caught sub-exception %@ on %@",__func__,subErr,self);
			else
				NSLog(@"\t\t%s caught sub-exception %@ on %@, target is %@",__func__,subErr,self,[targetObj class]);
		}
		pool = [[NSAutoreleasePool alloc] init];
		goto STARTLOOP;
	}
	
	[pool release];
	os_unfair_lock_lock(&valLock);
	running = NO;
	os_unfair_lock_unlock(&valLock);
	//NSLog(@"\t\t%s - FINSHED",__func__);
}
- (void) threadProc	{
	
}
- (void) pause	{
	os_unfair_lock_lock(&valLock);
	paused = YES;
	os_unfair_lock_unlock(&valLock);
}
- (void) resume	{
	os_unfair_lock_lock(&valLock);
	paused = NO;
	os_unfair_lock_unlock(&valLock);
}
- (void) stop	{
	os_unfair_lock_lock(&valLock);
	if (!running)	{
		os_unfair_lock_unlock(&valLock);
		return;
	}
	bail = YES;
	os_unfair_lock_unlock(&valLock);
}
- (void) stopAndWaitUntilDone	{
	//NSLog(@"%s",__func__);
	[self stop];
	BOOL			tmpRunning = NO;
	
	os_unfair_lock_lock(&valLock);
	tmpRunning = running;
	os_unfair_lock_unlock(&valLock);
	
	while (tmpRunning)	{
		//NSLog(@"\twaiting");
		//pthread_yield_np();
		usleep(100);
		
		os_unfair_lock_lock(&valLock);
		tmpRunning = running;
		os_unfair_lock_unlock(&valLock);
	}
	
}
- (double) interval	{
	return interval;
}
- (void) setInterval:(double)i	{
	interval = (i > maxInterval) ? maxInterval : i;
}
- (BOOL) running	{
	BOOL		returnMe = NO;
	os_unfair_lock_lock(&valLock);
	returnMe = running;
	os_unfair_lock_unlock(&valLock);
	return returnMe;
}


@synthesize maxInterval;


@end
