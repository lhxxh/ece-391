.data					# section declaration

        # Useful offset constants for accessing members of a 
        # struct mp1_blink_struct structure
        LOCATION   = 0    
        ON_CHAR    = 2
        OFF_CHAR   = 3 
        ON_LENGTH  = 4
        OFF_LENGTH = 6
        COUNTDOWN  = 8
        STATUS     = 10
        NEXT       = 12

        STRUCT_SIZE = 16

# Pointer to head of list (initialized to NULL)
mp1_list_head:
        .long   0

.text					# section declaration

# Export the function symbol names

.global mp1_rtc_tasklet
.global mp1_ioctl

# void mp1_poke(void);
#
# Interface: Register-based arguments (not C-style)
#    Inputs: %cl  - The byte you wish to write
#            %eax - Offset from the start of video memory that you wish
#                   to write to
#   Outputs: Text-mode video screen is written to at location %eax with
#            the byte in %cl
# Registers: Clobbers EDX
mp1_poke:
        
	movl    vmem_base_addr(,1),%edx
	movb    %cl,(%edx,%eax,1)
	ret

mp1_rtc_tasklet:
        pushl   %ebp
        movl    %esp,%ebp
        pushl   %ebx
        pushl   %esi
        pushl   %edi    

        movl    mp1_list_head,%ebx                      # check if ptr of list (%ebx) is null, if it is, then return
   mp1_rtc_tasklet_for_loop:
        cmpl    $0,%ebx
        je      no_elem
        
        decw    COUNTDOWN(%ebx)                         # decrement the specific elem's COUNTDOWN and check whether it reaches 0
        cmpw    $0,COUNTDOWN(%ebx)
        je      examine_status   

   next_elem:
        movl    NEXT(%ebx),%ebx                         # go to next element
        jmp     mp1_rtc_tasklet_for_loop

   examine_status:
        cmpw    $0,STATUS(%ebx)                         # if it is off, go to switch_to_on, else if it is on, go to switch_to_off
        je      switch_to_on
        cmpw    $1,STATUS(%ebx)
        je      switch_to_off

   switch_to_on:
        movzbl  ON_CHAR(%ebx),%ecx                      # load on char to (%ecx) and offset to (%eax) then call mp1_poke
        movzwl  LOCATION(%ebx),%eax
        shll    $1,%eax
        pushl   %edx
        call    mp1_poke
        popl    %edx

        movzwl  ON_LENGTH(%ebx),%ecx                    # copy ON_LENGTH to COUNTDOWN and go to next elem
        movw    %cx,COUNTDOWN(%ebx)
        movw    $1,STATUS(%ebx)
        jmp     next_elem

   switch_to_off:
        movzbl  OFF_CHAR(%ebx),%ecx
        movzwl  LOCATION(%ebx),%eax
        shll    $1,%eax
        pushl   %edx
        call    mp1_poke
        popl    %edx

        movzwl  OFF_LENGTH(%ebx),%ecx
        movw    %cx,COUNTDOWN(%ebx)
        movw    $0,STATUS(%ebx)
        jmp     next_elem
        
   no_elem:                                             # if no element any more (%ebx==0),then return
        popl    %edi
        popl    %esi
        popl    %ebx
        leave
        ret
# this function serves as a jump table 
mp1_ioctl:
        movl    8(%esp),%eax
        cmpl    $3,%eax
        ja      mp1_ioctl_cmd_error
        jmp     *jumptable(,%eax,4)

# this sub-function handles the error cmd value in mp1_ioctl
mp1_ioctl_cmd_error:
        movl    $-1,%eax
        ret
# this function adds element to the list
mp1_ioctl_add:
        pushl   %ebp
        movl    %esp,%ebp
        pushl   %ebx
        pushl   %esi
        pushl   %edi
         
        movl    8(%ebp),%ebx                # if ptr==null (in %ebx), then fail
        cmpl    $0,%ebx
        je      mp1_ioctl_add_fail
        
        pushl   %eax                        # call mp1_malloc
        pushl   %ecx
        pushl   %edx
        pushl   $STRUCT_SIZE
        call    mp1_malloc
        movl    %eax,%esi
        addl    $4,%esp
        popl    %edx
        popl    %ecx
        popl    %eax

        cmpl    $0,%esi                     # if mp1_malloc returns null (in %esi), then fail
        je      mp1_ioctl_add_fail

        pushl   %eax                        # call mp1_copy_from_user
        pushl   %ecx
        pushl   %edx
        pushl   $STRUCT_SIZE
        pushl   %ebx
        pushl   %esi
        call    mp1_copy_from_user
        movl    %eax,%edi
        addl    $12,%esp
        popl    %edx
        popl    %ecx
        popl    %eax

        cmpl    $0,%edi                    # if mp1_copy_from_user returns non-zero value(in %edi), then free malloc
        jne     mp1_ioctl_add_free_malloc  


        movzwl  LOCATION(%esi),%ecx        # if location (in %ecx) is greater than 80*25-1, then free malloc
        cmpl    $80*25-1,%ecx
        ja      mp1_ioctl_add_free_malloc

        movzwl  ON_LENGTH(%esi),%ecx       # COUNTDOWN=ON_LENGTH, STATUS=1,insert to head of list
        movw    %cx,COUNTDOWN(%esi)
        movw    $1,STATUS(%esi)
        movl    mp1_list_head,%ecx
        movl    %ecx,NEXT(%esi)
        movl    %esi,mp1_list_head

        movzwl  LOCATION(%esi),%eax        # call mp1_poke, %eax=offset,%cl=ON_CHAR
        shll    $1,%eax
        movzbl  ON_CHAR(%esi),%ecx
        pushl   %edx
        call mp1_poke
        popl    %edx

        movl    $0,%eax                   # return suceess(put 0 into %eax)
        popl    %edi
        popl    %esi
        popl    %ebx
        leave
        ret
# this sub-function help mp1_ioctl_add return -1 if any case fail
mp1_ioctl_add_fail:
        movl    $-1,%eax                  # return unsuccess(put -1 into %eax)
        popl    %edi
        popl    %esi
        popl    %ebx
        leave
        ret
# this sub-function help mp1_ioctl_add free malloc if mp1_malloc is used before  
mp1_ioctl_add_free_malloc:
        pushl   %eax
        pushl   %ecx
        pushl   %edx
        pushl   %esi
        call    mp1_free
        addl    $4,%esp
        popl    %edx
        popl    %ecx
        popl    %eax
        jmp     mp1_ioctl_add_fail
# this function removes element in the list   
mp1_ioctl_remove:                                 # the location is 2 byte as argument and call linked_list_search,return 0 as success
        pushl   %ebp
        movl    %esp,%ebp
        pushl   %ebx
        pushl   %edi
        pushl   %esi

        movl    8(%ebp),%ebx                     # call function linked_list_search with parameter in (%ebx location)
        pushl   %eax
        pushl   %ecx
        pushl   %edx
        pushw   %bx
        call    linked_list_search
        movl    %eax,%ebx
        addl    $2,%esp
        popl    %edx
        popl    %ecx
        popl    %eax

        cmpl    $0,%ebx                         # test whether find the kernel-ptr(%ebx)
        je      mp1_ioctl_remove_fail

        cmpl    mp1_list_head,%ebx              # check whether the kernel-ptr is head
        je      kernel_ptr_is_head

        movl    mp1_list_head,%edi              # load list head and find the previous ptr (%edi), when kernel-ptr is not the head
    mp1_ioctl_remove_for_loop:
        cmpl    NEXT(%edi),%ebx
        je      find_the_previous_elem
        movl    NEXT(%edi),%edi
        jmp     mp1_ioctl_remove_for_loop

    kernel_ptr_is_head:
        movl    NEXT(%ebx),%eax                 # change the list head and free the elem
        movl    %eax,mp1_list_head
        pushl   %eax
        pushl   %ecx
        pushl   %edx
        pushl   %ebx
        call    mp1_free
        addl    $4,%esp
        popl    %edx
        popl    %ecx
        popl    %eax
        jmp     mp1_ioctl_remove_success

    find_the_previous_elem:                     # change previous next and free the element
        movl    NEXT(%ebx),%eax
        movl    %eax,NEXT(%edi)
        pushl   %eax
        pushl   %ecx
        pushl   %edx
        pushl   %ebx
        call    mp1_free
        addl    $4,%esp
        popl    %edx
        popl    %ecx
        popl    %eax

    mp1_ioctl_remove_success:
        movl    $0,%eax
        popl    %esi
        popl    %edi
        popl    %ebx
        leave
	    ret
# this function deals with failure case in mp1_ioctl_remove, return -1 as unsuccess
mp1_ioctl_remove_fail:
        movl    $-1,%eax
        popl    %esi
        popl    %edi
        popl    %ebx
        leave
        ret
# this function find the element in the list  
mp1_ioctl_find:                                  # location is 2 byte as argument and call linked_list_search,return 0 as success
        pushl   %ebp
        movl    %esp,%ebp
        pushl   %ebx
        pushl   %edi
        pushl   %esi

        movl    8(%ebp),%ebx                     # load user-ptr into (%ebx), check if it is null
        cmpl    $0,%ebx
        je      mp1_ioctl_find_fail

        pushl   %eax                             # call linked_list_search and put return kernel-ptr in (%edi)
        pushl   %ecx
        pushl   %edx
        pushw   LOCATION(%ebx)
        call    linked_list_search
        movl    %eax,%edi
        addl    $2,%esp
        popl    %edx
        popl    %ecx
        popl    %eax

        cmpl    $0,%edi                          # check whether the elem has been founded
        je      mp1_ioctl_find_fail

        pushl   %eax                             # call copy_to_user, return uncopied data in (%esi)
        pushl   %ecx
        pushl   %edx
        pushl   $STRUCT_SIZE
        pushl   %edi
        pushl   %ebx
        call    mp1_copy_to_user
        movl    %eax,%esi
        addl    $12,%esp
        popl    %edx
        popl    %ecx
        popl    %eax

        cmpl    $0,%esi                         # check whether non-copied value is non-zero
        jne     mp1_ioctl_find_fail

        movl    $0,%eax                         # return success
        popl    %esi
        popl    %edi
        popl    %ebx
        leave
	    ret
# this function deals with the failure case in mp1_ioctl_find,return -1
mp1_ioctl_find_fail:
        movl    $-1,%eax
        popl    %esi
        popl    %edi
        popl    %ebx
        leave
        ret
# this function substitute one element with another
mp1_ioctl_sync:                                 # the location is 2 byte as argument and call linked_list_search
        pushl   %ebp
        movl    %esp,%ebp
        pushl   %ebx
        pushl   %edi
        pushl   %esi

        movl    8(%ebp),%ebx                    # load the first location to (%bx) and the second location to (%di) 
        movzwl  %bx,%edi                        
        shrl    $16,%ebx

        pushl   %eax                            # find the first struct ptr (into %ebx)
        pushl   %ecx
        pushl   %edx
        pushw   %bx
        call    linked_list_search
        movl    %eax,%ebx
        addl    $2,%esp
        popl    %edx
        popl    %ecx
        popl    %eax

        cmpl    $0,%ebx                         # check whether the first struct being found
        je      mp1_ioctl_sync_fail

        pushl   %eax                            # find the second struct ptr (into %edi)
        pushl   %ecx
        pushl   %edx 
        pushw   %di
        call    linked_list_search
        movl    %eax,%edi
        addl    $2,%esp
        popl    %edx
        popl    %ecx
        popl    %eax

        cmpl    $0,%edi                         # check whether the second elem being found
        je      mp1_ioctl_sync_fail

        movzwl  ON_LENGTH(%ebx),%esi            # copy from the first struct to the second struct
        movw    %si,ON_LENGTH(%edi)
        movzwl  OFF_LENGTH(%ebx),%esi
        movw    %si,OFF_LENGTH(%edi)
        movzwl  COUNTDOWN(%ebx),%esi
        movw    %si,COUNTDOWN(%edi)
        movzwl  STATUS(%ebx),%esi
        movw    %si,STATUS(%edi)

        movzwl  STATUS(%edi),%esi              # check STATUS
        cmpl    $0,%esi
        je      print_off_char
        cmpl    $1,%esi
        je      print_on_char

# this sub-function is to print off_char 
    print_off_char:
        movzbl  OFF_CHAR(%edi),%ecx
        movzwl  LOCATION(%edi),%eax
        shll    $1,%eax
        pushl   %edx
        call    mp1_poke
        popl    %edx

        movl    $0,%eax
        popl    %esi   
        popl    %edi
        popl    %ebx
        leave
        ret
# this sub-function is to print on_char
    print_on_char:
        movzbl  ON_CHAR(%edi),%ecx
        movzwl  LOCATION(%edi),%eax
        shll    $1,%eax
        pushl   %edx
        call    mp1_poke
        popl    %edx

        movl    $0,%eax
        popl    %esi
        popl    %edi
        popl    %ebx
        leave
        ret
# this function deals with the failure case in mp1_ioctl_sync and return -1 as unsuccess
mp1_ioctl_sync_fail:                            
        movl    $-1,%eax
        popl    %esi
        popl    %edi
        popl    %ebx
        leave        
        ret
# this is a helper function to serves as searching tool 
# its c protptype is struct* linked_list_search(unsigned_16 location)
# return 0 if fail to find, not assuming the list has elements
linked_list_search:
        pushl   %ebp
        movl    %esp,%ebp
        pushl   %ebx
        pushl   %edi
        pushl   %esi

        movzwl  8(%ebp),%ebx                # load location into (%ebx) and load head into (%edi)
        cmpl    $80*25-1,%ebx               # check if the location is within 80*25 and whether head has elem
        ja      linked_list_search_fail
        movl    mp1_list_head,%edi

    linked_list_search_for_loop:            # loop to find the exact elem, if cannot find, throw to fail case
        cmpl    $0,%edi
        je      linked_list_search_fail                                        
        cmpw    LOCATION(%edi),%bx
        je      find_the_elem
        movl    NEXT(%edi),%edi
        jmp     linked_list_search_for_loop

# this function deals with the fail case in linked_list_search, return 0
linked_list_search_fail:
        movl    $0,%eax
        popl    %esi
        popl    %edi
        popl    %ebx
        leave
        ret
# this function deals with the case the elem being found
find_the_elem:
        movl    %edi,%eax
        popl    %esi
        popl    %edi
        popl    %ebx
        leave
        ret
# the jumptable used in mp1_ioctl
jumptable:
.long mp1_ioctl_add,mp1_ioctl_remove,mp1_ioctl_find,mp1_ioctl_sync
.end
